import CADCore

public struct BSplineSurfaceEmbeddingValidator: Sendable {
    public var maximumLocalSubdivisionDepth: Int
    public var maximumCellCount: Int
    public var maximumPairSubdivisionDepth: Int
    public var maximumPairCellCount: Int

    public init(
        maximumLocalSubdivisionDepth: Int = 14,
        maximumCellCount: Int = 65_536,
        maximumPairSubdivisionDepth: Int = 24,
        maximumPairCellCount: Int = 262_144
    ) {
        self.maximumLocalSubdivisionDepth = maximumLocalSubdivisionDepth
        self.maximumCellCount = maximumCellCount
        self.maximumPairSubdivisionDepth = maximumPairSubdivisionDepth
        self.maximumPairCellCount = maximumPairCellCount
    }

    public func validate(
        _ surface: BSplineSurface3D,
        uDomain: ParameterDomain,
        vDomain: ParameterDomain,
        tolerance: ModelingTolerance,
        allowStationaryBoundaryParameterization: Bool = false
    ) throws {
        try tolerance.validate()
        try surface.validate(tolerance: tolerance)
        guard maximumLocalSubdivisionDepth >= 0,
              maximumCellCount > 0,
              maximumPairSubdivisionDepth >= 0,
              maximumPairCellCount > 0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-spline surface embedding limits must be positive."
            )
        }
        guard surface.uDegree > 0, surface.vDegree > 0 else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                tolerance: tolerance,
                message: "A globally embedded B-spline surface requires positive parameter degrees."
            )
        }
        let bounds = try retainedBounds(
            surface: surface,
            uDomain: uDomain,
            vDomain: vDomain,
            tolerance: tolerance
        )
        let patches = try clippedPatches(
            surface: surface,
            bounds: bounds,
            tolerance: tolerance
        )
        guard patches.isEmpty == false else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "The requested B-spline surface domain contains no non-degenerate knot span."
            )
        }
        guard patches.count <= maximumCellCount else {
            throw resourceLimit(residual: Double(patches.count), tolerance: tolerance,
                message: "B-spline surface embedding exhausted its local cell budget.")
        }
        var cells = try patches.map { try Cell(patch: $0, depth: 0,
            stationaryDomain: allowStationaryBoundaryParameterization ? bounds : nil) }

        try certifyLocalInjectivity(
            cells: &cells,
            normalAt: { try surface.normal(u: $0, v: $1, tolerance: tolerance) },
            tolerance: tolerance
        )
        try certifySeparatedCells(
            cells,
            pointAt: { try surface.point(u: $0, v: $1, tolerance: tolerance) },
            tolerance: tolerance
        )
    }

    private struct RetainedBounds: Sendable, Hashable {
        let uLower: Double
        let uUpper: Double
        let vLower: Double
        let vUpper: Double
    }

    private struct Cell: Sendable {
        let patch: RationalBezierSurfacePatch3D
        let depth: Int
        let differentialBounds: RationalBezierSurfaceDifferentialBounds
        let bounds: BoundingBox3D
        let stationaryDomain: RetainedBounds?
        let stationaryBoundaries: Set<SurfaceParameterBoundary>

        init(patch: RationalBezierSurfacePatch3D, depth: Int, stationaryDomain: RetainedBounds?) throws {
            self.patch = patch
            self.depth = depth
            self.stationaryDomain = stationaryDomain
            self.stationaryBoundaries = stationaryDomain.map {
                RationalBezierSurfaceDifferentialBounds.outerBoundaries(of: patch,
                    uDomain: .closed($0.uLower, $0.uUpper), vDomain: .closed($0.vLower, $0.vUpper))
            } ?? []
            self.differentialBounds = RationalBezierSurfaceDifferentialBounds(patch: patch,
                stationaryBoundaries: stationaryBoundaries)
            self.bounds = try patch.boundingBox()
        }
    }

    private struct ProjectionAxes: Sendable {
        let first: Vector3D
        let second: Vector3D
    }

    private struct PairCell: Sendable {
        let difference: RationalBezierSurfaceSurfaceDifferencePatch
        let depth: Int
    }

    private func retainedBounds(
        surface: BSplineSurface3D,
        uDomain: ParameterDomain,
        vDomain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> RetainedBounds {
        guard case let .closed(uLower, uUpper) = uDomain,
              case let .closed(vLower, vUpper) = vDomain,
              try surface.uDomain.containsSpan(
                  from: uLower,
                  to: uUpper,
                  tolerance: tolerance
              ),
              try surface.vDomain.containsSpan(
                  from: vLower,
                  to: vUpper,
                  tolerance: tolerance
              ) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-spline surface embedding requires contained closed parameter domains."
            )
        }
        return RetainedBounds(
            uLower: uLower,
            uUpper: uUpper,
            vLower: vLower,
            vUpper: vUpper
        )
    }

    private func clippedPatches(
        surface: BSplineSurface3D,
        bounds: RetainedBounds,
        tolerance: ModelingTolerance
    ) throws -> [RationalBezierSurfacePatch3D] {
        let parameterTolerance = max(
            tolerance.relative * max(
                abs(bounds.uLower),
                abs(bounds.uUpper),
                abs(bounds.vLower),
                abs(bounds.vUpper),
                1.0
            ),
            Double.ulpOfOne * 256.0
        )
        return try BSplineSurfaceBezierDecomposer()
            .surfacePatches(surface: surface, tolerance: tolerance)
            .compactMap { patch in
                let uLower = max(patch.uLower, bounds.uLower)
                let uUpper = min(patch.uUpper, bounds.uUpper)
                let vLower = max(patch.vLower, bounds.vLower)
                let vUpper = min(patch.vUpper, bounds.vUpper)
                guard uUpper - uLower > parameterTolerance,
                      vUpper - vLower > parameterTolerance else {
                    return nil
                }
                return try patch.trimmed(
                    uFrom: uLower,
                    uTo: uUpper,
                    vFrom: vLower,
                    vTo: vUpper,
                    tolerance: tolerance
                )
            }
    }

    private func certifyLocalInjectivity(
        cells: inout [Cell],
        normalAt: (Double, Double) throws -> Vector3D,
        tolerance: ModelingTolerance
    ) throws {
        var index = 0
        while index < cells.count {
            guard cells.count <= maximumCellCount else {
                throw resourceLimit(
                    residual: Double(cells.count),
                    tolerance: tolerance,
                    message: "B-spline surface embedding exhausted its local cell budget."
                )
            }
            if projectionProvesInjective(bounds: [cells[index].differentialBounds]) {
                index += 1
            } else {
                try rejectSampledSingularity(
                    in: cells[index].patch,
                    normalAt: normalAt,
                    tolerance: tolerance,
                    stationaryBoundaries: cells[index].stationaryBoundaries
                )
                try subdivide(
                    indexes: [index],
                    cells: &cells,
                    tolerance: tolerance
                )
            }
        }
        // Restriction preserves the local injectivity proved above. Refining a
        // touching region does not invalidate proofs for the unchanged cells.
        var certifiedRegions: Set<RetainedBounds> = []
        while true {
            guard cells.count <= maximumCellCount else {
                throw resourceLimit(residual: Double(cells.count), tolerance: tolerance,
                    message: "B-spline surface embedding exhausted its local cell budget.")
            }
            guard let unresolved = firstUnresolvedTouchingRegion(in: cells, certifiedRegions: &certifiedRegions) else {
                return
            }
            for index in unresolved {
                try rejectSampledSingularity(
                    in: cells[index].patch,
                    normalAt: normalAt,
                    tolerance: tolerance,
                    stationaryBoundaries: cells[index].stationaryBoundaries
                )
            }
            let coarsestDepth = unresolved.map { cells[$0].depth }.min()!
            try subdivide(
                indexes: unresolved.filter { cells[$0].depth == coarsestDepth },
                cells: &cells,
                tolerance: tolerance
            )
        }
    }

    private func rejectSampledSingularity(
        in patch: RationalBezierSurfacePatch3D,
        normalAt: (Double, Double) throws -> Vector3D,
        tolerance: ModelingTolerance,
        stationaryBoundaries: Set<SurfaceParameterBoundary>
    ) throws {
        for uFraction in [0.0, 0.5, 1.0] {
            for vFraction in [0.0, 0.5, 1.0] {
                if (uFraction == 0 && stationaryBoundaries.contains(.uLower))
                    || (uFraction == 1 && stationaryBoundaries.contains(.uUpper))
                    || (vFraction == 0 && stationaryBoundaries.contains(.vLower))
                    || (vFraction == 1 && stationaryBoundaries.contains(.vUpper)) { continue }
                let sample = parameter(
                    in: patch,
                    uFraction: uFraction,
                    vFraction: vFraction
                )
                do {
                    _ = try normalAt(sample.x, sample.y)
                } catch let error as KernelError where error.code == .singularSystem {
                    throw KernelError(
                        phase: .geometry,
                        code: .singularGeometry,
                        residual: error.residual,
                        tolerance: tolerance,
                        message: "The B-spline surface contains a sampled singular parameter in the retained domain."
                    )
                }
            }
        }
    }

    private func firstUnresolvedTouchingRegion(in cells: [Cell],
        certifiedRegions: inout Set<RetainedBounds>) -> [Int]? {
        guard cells.count > 1 else { return nil }
        let domains = cells.map { RetainedBounds(uLower: $0.patch.uLower, uUpper: $0.patch.uUpper,
            vLower: $0.patch.vLower, vUpper: $0.patch.vUpper) }
        let order = domains.indices.sorted {
            domains[$0].uLower == domains[$1].uLower ? $0 < $1 : domains[$0].uLower < domains[$1].uLower
        }
        var hulls = domains
        func build(_ lower: Int, _ upper: Int) -> RetainedBounds {
            let middle = (lower + upper) / 2
            var hull = domains[order[middle]]
            for range in [lower..<middle, (middle + 1)..<upper] where !range.isEmpty {
                let child = build(range.lowerBound, range.upperBound)
                hull = RetainedBounds(uLower: min(hull.uLower, child.uLower),
                    uUpper: max(hull.uUpper, child.uUpper), vLower: min(hull.vLower, child.vLower),
                    vUpper: max(hull.vUpper, child.vUpper))
            }
            hulls[middle] = hull
            return hull
        }
        _ = build(0, order.count)
        func candidates(_ region: RetainedBounds, strict: Bool) -> [Int] {
            func overlaps(_ bounds: RetainedBounds) -> Bool {
                let du = min(bounds.uUpper, region.uUpper) - max(bounds.uLower, region.uLower)
                let dv = min(bounds.vUpper, region.vUpper) - max(bounds.vLower, region.vLower)
                return strict ? du > 0 && dv > 0 : du >= 0 && dv >= 0
            }
            var result: [Int] = []
            func visit(_ lower: Int, _ upper: Int) {
                guard lower < upper else { return }
                let middle = (lower + upper) / 2
                guard overlaps(hulls[middle]) else { return }
                let index = order[middle]
                if overlaps(domains[index]) { result.append(index) }
                visit(lower, middle)
                visit(middle + 1, upper)
            }
            visit(0, order.count)
            return result.sorted()
        }
        for firstIndex in 0..<(cells.count - 1) {
            let first = domains[firstIndex]
            for secondIndex in candidates(first, strict: false) where secondIndex > firstIndex {
                let second = domains[secondIndex]
                let region = RetainedBounds(uLower: min(first.uLower, second.uLower),
                    uUpper: max(first.uUpper, second.uUpper), vLower: min(first.vLower, second.vLower),
                    vUpper: max(first.vUpper, second.vUpper))
                if certifiedRegions.contains(region) { continue }
                let regionIndexes: [Int]
                // Two cells sharing a full side already cover their bounding
                // rectangle. Corner contacts and unequal sides still need every
                // cell in that rectangle to avoid proving a disconnected domain.
                if (first.uLower == second.uLower && first.uUpper == second.uUpper
                    && (first.vUpper == second.vLower || second.vUpper == first.vLower))
                    || (first.vLower == second.vLower && first.vUpper == second.vUpper
                        && (first.uUpper == second.uLower || second.uUpper == first.uLower)) {
                    regionIndexes = [firstIndex, secondIndex]
                } else {
                    regionIndexes = candidates(region, strict: true)
                }
                let regionBounds = regionIndexes.map { cells[$0].differentialBounds }
                if projectionProvesInjective(bounds: regionBounds) == false {
                    return regionIndexes
                }
                if certifiedRegions.count < maximumPairCellCount { certifiedRegions.insert(region) }
            }
        }
        return nil
    }

    private func subdivide(
        indexes: [Int],
        cells: inout [Cell],
        tolerance: ModelingTolerance
    ) throws {
        let uniqueIndexes = Array(Set(indexes)).sorted(by: >)
        guard uniqueIndexes.isEmpty == false else {
            throw resourceLimit(
                residual: 0.0,
                tolerance: tolerance,
                message: "B-spline surface embedding found an empty unresolved region."
            )
        }
        for index in uniqueIndexes {
            let cell = cells[index]
            guard cell.depth < maximumLocalSubdivisionDepth else {
                throw resourceLimit(
                    residual: Double(cell.depth),
                    tolerance: tolerance,
                    message: "B-spline surface embedding could not certify local injectivity within the subdivision limit."
                )
            }
            guard cells.count <= maximumCellCount - 3 else {
                throw resourceLimit(residual: Double(cells.count) + 3, tolerance: tolerance,
                    message: "B-spline surface embedding exhausted its local cell budget.")
            }
            let children = try cell.patch.subdivided().map {
                try Cell(patch: $0, depth: cell.depth + 1, stationaryDomain: cell.stationaryDomain)
            }
            cells.remove(at: index)
            cells.insert(contentsOf: children, at: index)
        }
    }

    private func projectionProvesInjective(
        bounds: [RationalBezierSurfaceDifferentialBounds]
    ) -> Bool {
        guard bounds.isEmpty == false else { return false }
        for axes in projectionCandidates(from: bounds) {
            var firstSign: Int?
            var secondSign: Int?
            var determinantSign: Int?
            var isConsistent = true
            for bound in bounds {
                guard let currentFirstSign = bound
                    .tangentUProjection(along: axes.first).sign,
                      let currentSecondSign = bound
                    .tangentVProjection(along: axes.second).sign,
                      let currentDeterminantSign = bound
                    .normalProjection(along: axes.first.cross(axes.second)).sign else {
                    isConsistent = false
                    break
                }
                if let firstSign, firstSign != currentFirstSign {
                    isConsistent = false
                    break
                }
                if let secondSign, secondSign != currentSecondSign {
                    isConsistent = false
                    break
                }
                if let determinantSign, determinantSign != currentDeterminantSign {
                    isConsistent = false
                    break
                }
                firstSign = currentFirstSign
                secondSign = currentSecondSign
                determinantSign = currentDeterminantSign
            }
            if isConsistent,
               let firstSign,
               let secondSign,
               let determinantSign,
               firstSign * secondSign * determinantSign > 0 {
                return true
            }
        }
        return false
    }

    private func projectionCandidates(
        from bounds: [RationalBezierSurfaceDifferentialBounds]
    ) -> [ProjectionAxes] {
        var candidates = [
            ProjectionAxes(first: .unitX, second: .unitY),
            ProjectionAxes(first: .unitY, second: .unitX),
            ProjectionAxes(first: .unitX, second: .unitZ),
            ProjectionAxes(first: .unitZ, second: .unitX),
            ProjectionAxes(first: .unitY, second: .unitZ),
            ProjectionAxes(first: .unitZ, second: .unitY),
        ]
        var accumulatedU = Vector3D.zero
        var accumulatedV = Vector3D.zero
        for bound in bounds {
            if let axes = tangentProjectionAxes(
                tangentU: bound.representativeTangentU,
                tangentV: bound.representativeTangentV
            ) {
                candidates.append(axes)
                accumulatedU = accumulatedU + axes.first
                accumulatedV = accumulatedV + axes.second
            }
        }
        if let aggregate = tangentProjectionAxes(
            tangentU: accumulatedU,
            tangentV: accumulatedV
        ) {
            candidates.append(aggregate)
        }
        return candidates
    }

    private func tangentProjectionAxes(
        tangentU: Vector3D,
        tangentV: Vector3D
    ) -> ProjectionAxes? {
        guard let first = unit(tangentU),
              let normal = unit(tangentU.cross(tangentV)),
              let second = unit(normal.cross(first)) else {
            return nil
        }
        return ProjectionAxes(first: first, second: second)
    }

    private func unit(_ vector: Vector3D) -> Vector3D? {
        let length = vector.length
        guard length.isFinite, length > Double.leastNormalMagnitude else {
            return nil
        }
        let result = vector / length
        return result.isFinite ? result : nil
    }

    /// Certifies separation over both complete finite parameter domains.
    /// Exact corner pairs permit only the nominated isolated point contacts.
    public func validateSeparation(
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        tolerance: ModelingTolerance,
        allowedCornerContacts: [(first: Point2D, second: Point2D)] = []
    ) throws {
        try tolerance.validate()
        try first.validate(tolerance: tolerance)
        try second.validate(tolerance: tolerance)
        guard allowedCornerContacts.count <= 4,
              Set(allowedCornerContacts.map(\.first)).count == allowedCornerContacts.count,
              Set(allowedCornerContacts.map(\.second)).count == allowedCornerContacts.count else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Permitted point contacts must use each source corner at most once.")
        }
        for contact in allowedCornerContacts {
            func corner(_ surface: BSplineSurface3D, _ uv: Point2D) -> Point3D? {
                guard case let .closed(u0, u1) = surface.uDomain,
                      case let .closed(v0, v1) = surface.vDomain,
                      (uv.x == u0 || uv.x == u1), (uv.y == v0 || uv.y == v1),
                      surface.uKnots.prefix(surface.uDegree + 1).allSatisfy({ $0 == u0 }),
                      surface.uKnots.suffix(surface.uDegree + 1).allSatisfy({ $0 == u1 }),
                      surface.vKnots.prefix(surface.vDegree + 1).allSatisfy({ $0 == v0 }),
                      surface.vKnots.suffix(surface.vDegree + 1).allSatisfy({ $0 == v1 }) else { return nil }
                let row = surface.controlPoints[uv.y == v0 ? 0 : surface.vControlPointCount - 1]
                return row[uv.x == u0 ? 0 : surface.uControlPointCount - 1]
            }
            guard let a = corner(first, contact.first), let b = corner(second, contact.second), a == b else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                    message: "Permitted point contact requires exactly identical clamped surface corners.")
            }
        }
        guard maximumPairSubdivisionDepth >= 0, maximumPairCellCount > 0,
              maximumCellCount > 0 else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Surface separation requires positive cell budgets and a nonnegative subdivision depth.")
        }
        let firstPatches = try BSplineSurfaceBezierDecomposer().surfacePatches(surface: first, tolerance: tolerance)
        let secondPatches = try BSplineSurfaceBezierDecomposer().surfacePatches(surface: second, tolerance: tolerance)
        guard !firstPatches.isEmpty, !secondPatches.isEmpty,
              firstPatches.count <= maximumCellCount, secondPatches.count <= maximumCellCount else {
            throw resourceLimit(residual: Double(max(firstPatches.count, secondPatches.count)), tolerance: tolerance,
                message: "Surface separation requires nonempty patch sets within the cell budget.")
        }
        let firstBounds = try firstPatches.map { try $0.boundingBox() }
        let secondBounds = try secondPatches.map { try $0.boundingBox() }
        var visited = 0
        for i in firstPatches.indices {
            for j in secondPatches.indices {
                try consumeSeparationCell(&visited, tolerance: tolerance)
                guard firstBounds[i].intersects(secondBounds[j], tolerance: tolerance.distance) else { continue }
                try certifyPairSeparation(first: firstPatches[i], second: secondPatches[j],
                    visited: &visited, tolerance: tolerance, allowedCornerContacts: allowedCornerContacts)
            }
        }
    }

    /// Certifies cross-surface separation except at two paired opposite boundaries.
    public func validateOppositeBoundaryContacts(
        first: BSplineSurface3D, firstBoundaries: [SurfaceParameterBoundary],
        second: BSplineSurface3D, secondBoundaries: [SurfaceParameterBoundary],
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        try first.validate(tolerance: tolerance)
        try second.validate(tolerance: tolerance)
        func opposite(_ sides: [SurfaceParameterBoundary]) -> Bool {
            Set(sides) == Set([.uLower, .uUpper]) || Set(sides) == Set([.vLower, .vUpper])
        }
        guard firstBoundaries.count == 2, secondBoundaries.count == 2,
              opposite(firstBoundaries), opposite(secondBoundaries),
              maximumLocalSubdivisionDepth >= 0, maximumPairSubdivisionDepth >= 0,
              maximumCellCount >= 4, maximumPairCellCount >= 4 else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Opposite-boundary admission requires two paired opposite sides and budgets for four chart pairs.")
        }
        func halves(_ surface: BSplineSurface3D, _ sides: [SurfaceParameterBoundary]) throws -> [BSplineSurface3D] {
            guard case let .closed(u0, u1) = surface.uDomain,
                  case let .closed(v0, v1) = surface.vDomain else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                    message: "Opposite-boundary admission requires finite charts.")
            }
            return try sides.map { side in
                switch side {
                case .uLower: return try surface.trimmed(uFrom: u0, uTo: u0 + (u1 - u0) * 0.5,
                    vFrom: v0, vTo: v1, tolerance: tolerance)
                case .uUpper: return try surface.trimmed(uFrom: u0 + (u1 - u0) * 0.5, uTo: u1,
                    vFrom: v0, vTo: v1, tolerance: tolerance)
                case .vLower: return try surface.trimmed(uFrom: u0, uTo: u1,
                    vFrom: v0, vTo: v0 + (v1 - v0) * 0.5, tolerance: tolerance)
                case .vUpper: return try surface.trimmed(uFrom: u0, uTo: u1,
                    vFrom: v0 + (v1 - v0) * 0.5, vTo: v1, tolerance: tolerance)
                }
            }
        }
        let a = try halves(first, firstBoundaries), b = try halves(second, secondBoundaries)
        let proof = Self(maximumLocalSubdivisionDepth: maximumLocalSubdivisionDepth,
            maximumCellCount: maximumCellCount / 4, maximumPairSubdivisionDepth: maximumPairSubdivisionDepth,
            maximumPairCellCount: maximumPairCellCount / 4)
        for i in a.indices {
            for j in b.indices {
                if i == j {
                    try proof.validateAdjacent(first: a[i], firstBoundary: firstBoundaries[i],
                        second: b[j], secondBoundary: secondBoundaries[j], tolerance: tolerance)
                } else {
                    try proof.validateSeparation(first: a[i], second: b[j], tolerance: tolerance)
                }
            }
        }
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Loft single-edge admission uses this
    // exact common-basis path. General seam basis reconciliation must be
    // implemented before claiming general adjacency.
    public func validateAdjacent(
        first: BSplineSurface3D,
        firstBoundary: SurfaceParameterBoundary,
        second: BSplineSurface3D,
        secondBoundary: SurfaceParameterBoundary,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        try first.validate(tolerance: tolerance)
        try second.validate(tolerance: tolerance)
        guard maximumCellCount > 0, maximumLocalSubdivisionDepth >= 0,
              maximumPairSubdivisionDepth >= 0, maximumPairCellCount > 0 else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Adjacent surface admission requires a positive cell budget.")
        }
        func chart(_ source: BSplineSurface3D, boundary: SurfaceParameterBoundary,
                   atUpper: Bool) -> BSplineSurface3D {
            let transpose = boundary == .uLower || boundary == .uUpper
            let reverse = (boundary == .uUpper || boundary == .vUpper) != atUpper
            func oriented<T>(_ values: [[T]]) -> [[T]] {
                let rows = transpose ? values[0].indices.map { i in values.map { $0[i] } } : values
                return reverse ? Array(rows.reversed()) : rows
            }
            let vKnots = transpose ? source.uKnots : source.vKnots
            let sum = vKnots[0] + vKnots[vKnots.count - 1]
            return BSplineSurface3D(uDegree: transpose ? source.vDegree : source.uDegree,
                vDegree: transpose ? source.uDegree : source.vDegree,
                uKnots: transpose ? source.vKnots : source.uKnots,
                vKnots: reverse ? vKnots.reversed().map { sum - $0 } : vKnots,
                controlPoints: oriented(source.controlPoints), weights: oriented(source.weights))
        }
        let a = chart(first, boundary: firstBoundary, atUpper: true)
        var b = chart(second, boundary: secondBoundary, atUpper: false)
        func clamped(_ s: BSplineSurface3D) -> Bool {
            s.uKnots.prefix(s.uDegree + 1).allSatisfy { $0 == s.uKnots[0] }
                && s.uKnots.suffix(s.uDegree + 1).allSatisfy { $0 == s.uKnots.last }
                && s.vKnots.prefix(s.vDegree + 1).allSatisfy { $0 == s.vKnots[0] }
                && s.vKnots.suffix(s.vDegree + 1).allSatisfy { $0 == s.vKnots.last }
        }
        if clamped(a), clamped(b), try straightSeamSeparates(a, b) {
            guard maximumCellCount >= 2, maximumPairCellCount >= 2 else {
                throw resourceLimit(residual: 2, tolerance: tolerance,
                    message: "Adjacent charts require local and pair budgets for both surfaces.")
            }
            let local = Self(maximumLocalSubdivisionDepth: maximumLocalSubdivisionDepth,
                maximumCellCount: maximumCellCount / 2,
                maximumPairSubdivisionDepth: maximumPairSubdivisionDepth,
                maximumPairCellCount: maximumPairCellCount / 2)
            for surface in [a, b] {
                try local.validate(surface, uDomain: surface.uDomain, vDomain: surface.vDomain,
                    tolerance: tolerance, allowStationaryBoundaryParameterization: true)
            }
            return
        }
        func seamResidual(_ points: [Point3D]) -> Double {
            guard let seam = a.controlPoints.last, seam.count == points.count else { return .infinity }
            return zip(seam, points).reduce(0) { max($0, ($1.0 - $1.1).length) }
        }
        let directResidual = seamResidual(b.controlPoints[0])
        let reversedResidual = seamResidual(Array(b.controlPoints[0].reversed()))
        if reversedResidual < directResidual {
            let sum = b.uKnots[0] + b.uKnots[b.uKnots.count - 1]
            b = BSplineSurface3D(uDegree: b.uDegree, vDegree: b.vDegree,
                uKnots: b.uKnots.reversed().map { sum - $0 }, vKnots: b.vKnots,
                controlPoints: b.controlPoints.map { Array($0.reversed()) },
                weights: b.weights.map { Array($0.reversed()) })
        }
        guard clamped(a), clamped(b), a.uDegree == b.uDegree, a.uKnots == b.uKnots,
              a.controlPoints.last == b.controlPoints.first, a.weights.last == b.weights.first else {
            throw resourceLimit(residual: min(directResidual, reversedResidual), tolerance: tolerance,
                message: "Adjacent spline charts require an exact common clamped boundary representation (degrees \(a.uDegree)/\(b.uDegree), knots equal: \(a.uKnots == b.uKnots), points equal: \(a.controlPoints.last == b.controlPoints.first), weights equal: \(a.weights.last == b.weights.first)).")
        }
        var cells: [Cell] = []
        for (index, surface) in [a, b].enumerated() {
            guard case let .closed(vLower, vUpper) = surface.vDomain,
                  case let .closed(uLower, uUpper) = surface.uDomain else {
                throw resourceLimit(residual: 0, tolerance: tolerance,
                    message: "Adjacent charts require finite parameter domains.")
            }
            let offset = Double(index)
            func mappedV(_ v: Double) -> Double { offset + (v - vLower) / (vUpper - vLower) }
            let patches = try BSplineSurfaceBezierDecomposer().surfacePatches(surface: surface, tolerance: tolerance)
            guard patches.count <= maximumCellCount - cells.count else {
                throw resourceLimit(residual: Double(patches.count), tolerance: tolerance,
                    message: "Adjacent spline charts exhausted the cell budget.")
            }
            let stationaryDomain = RetainedBounds(uLower: uLower, uUpper: uUpper,
                vLower: offset, vUpper: offset + 1)
            cells.append(contentsOf: try patches.map { patch in
                try Cell(patch: RationalBezierSurfacePatch3D(controlPoints: patch.controlPoints,
                    weights: patch.weights, uLower: patch.uLower, uUpper: patch.uUpper,
                    vLower: mappedV(patch.vLower), vUpper: mappedV(patch.vUpper)),
                    depth: 0, stationaryDomain: stationaryDomain)
            })
        }
        if projectionProvesInjective(bounds: cells.map(\.differentialBounds)) { return }
        func sourceParameter(_ v: Double) -> (BSplineSurface3D, Double) {
            let surface = v <= 1 ? a : b
            let lower = surface.vKnots[surface.vDegree]
            let upper = surface.vKnots[surface.vKnots.count - surface.vDegree - 1]
            return (surface, lower + (v <= 1 ? v : v - 1) * (upper - lower))
        }
        func pointAt(_ u: Double, _ v: Double) throws -> Point3D {
            let (surface, parameter) = sourceParameter(v)
            return try surface.point(u: u, v: parameter, tolerance: tolerance)
        }
        var comparisons = 0
        for i in cells.indices {
            for j in cells.indices where j > i {
                try consumeSeparationCell(&comparisons, tolerance: tolerance)
                try rejectSampledCoincidence(first: cells[i].patch, second: cells[j].patch,
                    pointAt: pointAt, tolerance: tolerance)
            }
        }
        try certifyLocalInjectivity(cells: &cells, normalAt: { u, v in
            let (surface, parameter) = sourceParameter(v)
            return try surface.normal(u: u, v: parameter, tolerance: tolerance)
        }, tolerance: tolerance)
        try certifySeparatedCells(cells, pointAt: pointAt, tolerance: tolerance)
    }

    private func straightSeamSeparates(_ a: BSplineSurface3D, _ b: BSplineSurface3D) throws -> Bool {
        let first = a.controlPoints[a.controlPoints.count - 1]
        let second = b.controlPoints[0]
        guard let start = first.first, let end = first.last, start != end,
              (second.first == start && second.last == end)
                || (second.first == end && second.last == start) else { return false }
        func coordinate(_ p: Point3D, _ axis: Int) -> Double {
            switch axis { case 0: p.x; case 1: p.y; default: p.z }
        }
        for axis in 0..<3 {
            let c1 = (axis + 1) % 3, c2 = (axis + 2) % 3
            guard coordinate(start, axis) != coordinate(end, axis) else { continue }
            func isStraight(_ points: [Point3D]) throws -> Bool {
                let increasing = coordinate(points[0], axis) < coordinate(points[points.count - 1], axis)
                for i in points.indices {
                    for other in [c1, c2] {
                        func projected(_ p: Point3D) -> Point2D {
                            Point2D(x: coordinate(p, axis), y: coordinate(p, other))
                        }
                        guard try RobustPredicates.orientation2D(projected(start), projected(end),
                            relativeTo: projected(points[i]), determinantTolerance: 0) == .zero else { return false }
                    }
                    if i > 0 {
                        let previous = coordinate(points[i - 1], axis), value = coordinate(points[i], axis)
                        if increasing ? value < previous : value > previous { return false }
                    }
                }
                return true
            }
            guard try isStraight(first), try isStraight(second) else { continue }
            // This third point only proposes a plane through the exact seam.
            // Every off-seam control must pass a strict orientation proof.
            let pa = a.controlPoints[0][a.controlPoints[0].count / 2]
            let pb = b.controlPoints[b.controlPoints.count - 1][b.controlPoints[0].count / 2]
            let third = start + (end - start).cross(pa - pb)
            guard third.x.isFinite, third.y.isFinite, third.z.isFinite else { return false }
            func sign(_ p: Point3D) throws -> RobustSign {
                try RobustPredicates.orientation3D(start, end, third,
                    relativeTo: p, determinantTolerance: 0)
            }
            let side = try sign(pa)
            guard side == .positive || side == .negative else { return false }
            let opposite: RobustSign = side == .positive ? .negative : .positive
            guard try sign(pb) == opposite else { return false }
            let firstSeparated = try a.controlPoints.dropLast().allSatisfy { row in
                try row.allSatisfy { try sign($0) == side }
            }
            let secondSeparated = try b.controlPoints.dropFirst().allSatisfy { row in
                try row.allSatisfy { try sign($0) == opposite }
            }
            if firstSeparated && secondSeparated { return true }
        }
        return false
    }

    private func consumeSeparationCell(_ visited: inout Int, tolerance: ModelingTolerance) throws {
        guard visited < maximumPairCellCount else {
            throw resourceLimit(residual: Double(visited), tolerance: tolerance,
                message: "B-spline surface separation exhausted its pair cell budget.")
        }
        visited += 1
    }

    private func certifyPairSeparation(
        first: RationalBezierSurfacePatch3D, second: RationalBezierSurfacePatch3D,
        visited: inout Int, tolerance: ModelingTolerance,
        allowedCornerContacts: [(first: Point2D, second: Point2D)] = []
    ) throws {
        var pending = [PairCell(difference: try RationalBezierSurfaceSurfaceDifferencePatch(
            first: first, second: second, tolerance: tolerance), depth: 0)]
        while let pair = pending.popLast() {
            if pair.depth > 0 { try consumeSeparationCell(&visited, tolerance: tolerance) }
            if pair.difference.excludesZero() { continue }
            if pair.difference.excludesZeroAlongSurfaceDirections(allowedCornerContacts: allowedCornerContacts) { continue }
            guard pair.depth < maximumPairSubdivisionDepth else {
                throw resourceLimit(residual: Double(pair.depth), tolerance: tolerance,
                    message: "B-spline surface separation could not exclude intersection within the subdivision limit.")
            }
            let parameterIndex = widestParameterIndex(pair.difference)
            pending.append(contentsOf: pair.difference.subdivided(parameterIndex: parameterIndex)
                .map { PairCell(difference: $0, depth: pair.depth + 1) })
        }
    }

    private func certifySeparatedCells(
        _ cells: [Cell],
        pointAt: (Double, Double) throws -> Point3D,
        tolerance: ModelingTolerance
    ) throws {
        guard cells.count > 1 else { return }
        if projectionProvesInjective(bounds: cells.map(\.differentialBounds)) { return }
        let axes: [KeyPath<Point3D, Double>] = [\.x, \.y, \.z]
        var axis = axes[0]
        var bestScore = Double.infinity
        for candidate in axes {
            var lower = Double.infinity, upper = -Double.infinity, width = 0.0
            for cell in cells {
                let minimum = cell.bounds.minimum[keyPath: candidate]
                let maximum = cell.bounds.maximum[keyPath: candidate]
                lower = min(lower, minimum)
                upper = max(upper, maximum)
                width += maximum - minimum
            }
            let score = upper > lower ? width / (upper - lower) : .infinity
            if score < bestScore { axis = candidate; bestScore = score }
        }
        let ordered = cells.indices.sorted {
            let a = cells[$0].bounds.minimum[keyPath: axis], b = cells[$1].bounds.minimum[keyPath: axis]
            return a == b ? $0 < $1 : a < b
        }
        var visitedPairCells = 0
        for firstOffset in 0..<(ordered.count - 1) {
            let firstIndex = ordered[firstOffset]
            for secondOffset in (firstOffset + 1)..<ordered.count {
                let secondIndex = ordered[secondOffset]
                guard cells[secondIndex].bounds.minimum[keyPath: axis]
                        <= cells[firstIndex].bounds.maximum[keyPath: axis] + tolerance.distance else { break }
                try consumeSeparationCell(&visitedPairCells, tolerance: tolerance)
                let first = cells[firstIndex].patch
                let second = cells[secondIndex].patch
                guard touches(first, second) == false else { continue }
                guard cells[firstIndex].bounds.intersects(cells[secondIndex].bounds,
                    tolerance: tolerance.distance) else { continue }
                try rejectSampledCoincidence(
                    first: first,
                    second: second,
                    pointAt: pointAt,
                    tolerance: tolerance
                )
                try certifyPairSeparation(first: first, second: second,
                    visited: &visitedPairCells, tolerance: tolerance)
            }
        }
    }

    private func rejectSampledCoincidence(
        first: RationalBezierSurfacePatch3D,
        second: RationalBezierSurfacePatch3D,
        pointAt: (Double, Double) throws -> Point3D,
        tolerance: ModelingTolerance
    ) throws {
        let fractions = [0.0, 0.5, 1.0]
        for firstU in fractions {
            for firstV in fractions {
                let firstParameter = parameter(
                    in: first,
                    uFraction: firstU,
                    vFraction: firstV
                )
                let firstPoint = try pointAt(firstParameter.x, firstParameter.y)
                for secondU in fractions {
                    for secondV in fractions {
                        let secondParameter = parameter(
                            in: second,
                            uFraction: secondU,
                            vFraction: secondV
                        )
                        if firstParameter == secondParameter { continue }
                        let secondPoint = try pointAt(secondParameter.x, secondParameter.y)
                        let residual = (firstPoint - secondPoint).length
                        guard residual > tolerance.distance else {
                            throw KernelError(
                                phase: .geometry,
                                code: .singularGeometry,
                                residual: residual,
                                tolerance: tolerance,
                                message: "Distinct B-spline surface parameters coincide within modeling tolerance."
                            )
                        }
                    }
                }
            }
        }
    }

    private func parameter(
        in patch: RationalBezierSurfacePatch3D,
        uFraction: Double,
        vFraction: Double
    ) -> Point2D {
        let uSpan = patch.uUpper - patch.uLower
        let vSpan = patch.vUpper - patch.vLower
        let u = patch.uLower + uSpan * uFraction
        let v = patch.vLower + vSpan * vFraction
        return Point2D(
            x: u,
            y: v
        )
    }

    private func widestParameterIndex(
        _ difference: RationalBezierSurfaceSurfaceDifferencePatch
    ) -> Int {
        let widths = [
            difference.firstUUpper - difference.firstULower,
            difference.firstVUpper - difference.firstVLower,
            difference.secondUUpper - difference.secondULower,
            difference.secondVUpper - difference.secondVLower,
        ]
        return widths.indices.max { first, second in
            if widths[first] != widths[second] {
                return widths[first] < widths[second]
            }
            return first > second
        } ?? 0
    }

    private func touches(
        _ first: RationalBezierSurfacePatch3D,
        _ second: RationalBezierSurfacePatch3D
    ) -> Bool {
        max(first.uLower, second.uLower) <= min(first.uUpper, second.uUpper)
            && max(first.vLower, second.vLower) <= min(first.vUpper, second.vUpper)
    }

    private func resourceLimit(
        residual: Double,
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .resourceLimitExceeded,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }
}
