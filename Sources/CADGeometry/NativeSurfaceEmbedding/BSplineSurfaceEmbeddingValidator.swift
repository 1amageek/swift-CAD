import CADCore

public struct BSplineSurfaceEmbeddingValidator: Sendable {
    public var maximumLocalSubdivisionDepth: Int
    public var maximumCellCount: Int
    public var maximumPairSubdivisionDepth: Int
    public var maximumPairCellCount: Int
    private let admission: NativeSurfaceEmbeddingAdmission

    public init(
        maximumLocalSubdivisionDepth: Int = 14,
        maximumCellCount: Int = 65_536,
        maximumPairSubdivisionDepth: Int = 24,
        maximumPairCellCount: Int = 262_144,
        admission: NativeSurfaceEmbeddingAdmission = .legacy
    ) {
        self.maximumLocalSubdivisionDepth = maximumLocalSubdivisionDepth
        self.maximumCellCount = maximumCellCount
        self.maximumPairSubdivisionDepth = maximumPairSubdivisionDepth
        self.maximumPairCellCount = maximumPairCellCount
        self.admission = admission
    }

    package static func stationaryPlanarSupport(
        for surface: BSplineSurface3D, tolerance: ModelingTolerance,
        admission: NativeSurfaceEmbeddingAdmission = .legacy
    ) throws -> Plane3D? {
        try surface.validate(tolerance: tolerance, consumeWork: { try admission.work(1) })
        guard surface.uDegree == 1, surface.vDegree == 1,
              surface.controlPoints.count == 2, surface.controlPoints[0].count == 2,
              surface.uKnots.count == 4, surface.vKnots.count == 4,
              surface.uKnots[0] == surface.uKnots[1], surface.uKnots[2] == surface.uKnots[3],
              surface.vKnots[0] == surface.vKnots[1], surface.vKnots[2] == surface.vKnots[3],
              surface.weights.allSatisfy({ $0.allSatisfy { $0 == 1 } }),
              let plane = try DefaultPlanarSurfaceResolver().exactPlane(for: .bSpline(surface), tolerance: tolerance)
        else { return nil }
        let points = [surface.controlPoints[0][0], surface.controlPoints[0][1],
                      surface.controlPoints[1][1], surface.controlPoints[1][0]]
        guard Set(points).count == 4 else { return nil }
        let n = plane.normal
        func projected(_ p: Point3D) -> Point2D {
            if abs(n.x) >= max(abs(n.y), abs(n.z)) { return Point2D(x: p.y, y: p.z) }
            if abs(n.y) >= abs(n.z) { return Point2D(x: p.z, y: p.x) }
            return Point2D(x: p.x, y: p.y)
        }
        var orientation: RobustSign?
        var zeroCount = 0
        var noncollinearIndex = 0
        for i in points.indices {
            let sign = try RobustPredicates.orientation2D(projected(points[i]),
                projected(points[(i + 1) % 4]), relativeTo: projected(points[(i + 2) % 4]),
                determinantTolerance: 0)
            if sign == .zero { zeroCount += 1; continue }
            guard sign == .positive || sign == .negative else { return nil }
            if let orientation, sign != orientation { return nil }
            orientation = sign
            noncollinearIndex = i
        }
        guard zeroCount == 1, orientation != nil else { return nil }
        let i = noncollinearIndex
        guard try RobustPredicates.orientation3D(points[i], points[(i + 1) % 4],
            points[(i + 2) % 4], relativeTo: points[(i + 3) % 4], determinantTolerance: 0) == .zero
        else { return nil }
        return Plane3D(origin: plane.origin, normal: plane.normal)
    }

    public func validate(
        _ surface: BSplineSurface3D,
        uDomain: ParameterDomain,
        vDomain: ParameterDomain,
        tolerance: ModelingTolerance,
        allowStationaryBoundaryParameterization: Bool = false
    ) throws {
        try tolerance.validate()
        try surface.validate(tolerance: tolerance, consumeWork: { try admission.work(1) })
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
        var originalContinuity = NativeSurfaceOriginalProofAllowance(admission: admission)
        try OriginalSplineSurfaceContinuityAdmission().validate(surface, tolerance: tolerance, usage: &originalContinuity)
        let bounds = try retainedBounds(
            surface: surface,
            uDomain: uDomain,
            vDomain: vDomain,
            tolerance: tolerance
        )
        if allowStationaryBoundaryParameterization,
           uDomain == surface.uDomain, vDomain == surface.vDomain,
           try Self.stationaryPlanarSupport(for: surface, tolerance: tolerance, admission: admission) != nil {
            return
        }
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
        let atlas = try NativeSurfaceOriginalAtlas(source: surface, over: SurfaceParameterBox(
                u: ScalarInterval(lower: bounds.uLower, upper: bounds.uUpper),
                v: ScalarInterval(lower: bounds.vLower, upper: bounds.vUpper)),
            maximumSpanCount: maximumCellCount, tolerance: tolerance, admission: admission)
        try admission.storageElements(patches.count, of: Cell.self)
        var cells = try patches.map { patch in
            let box = try Self.parameterBox(of: patch)
            let law = try atlas.selected(over: box, admission: admission)
            return try Cell(patch: patch, depth: 0,
                original: .init(law: law, nativeDomain: box, workingDomain: box),
            stationaryDomain: allowStationaryBoundaryParameterization ? bounds : nil, admission: admission) }

        try certifyLocalInjectivity(
            cells: &cells,
            normalAt: {
                try NativeSurfaceEmbeddingPreparationReservation.point(surface, admission: admission)
                return try surface.normal(u: $0, v: $1, tolerance: tolerance)
            },
            tolerance: tolerance
        )
        try certifySeparatedCells(
            cells,
            point: {
                try NativeSurfaceEmbeddingPreparationReservation.point(surface, admission: admission)
                return try surface.point(u: $0, v: $1, tolerance: tolerance)
            },
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
        let original: NativeSurfaceOriginalCellChart
        let stationaryBoundaries: Set<SurfaceParameterBoundary>

        init(patch: RationalBezierSurfacePatch3D, depth: Int, original: NativeSurfaceOriginalCellChart, stationaryDomain: RetainedBounds?,
            admission: NativeSurfaceEmbeddingAdmission) throws {
            try admission.cell(depth: depth)
            try admission.storageElements(1, of: Cell.self)
            try admission.storageElements(8, of: SurfaceParameterBoundary.self)
            self.patch = patch
            self.original = original
            self.depth = depth
            self.stationaryDomain = stationaryDomain
            self.stationaryBoundaries = stationaryDomain.map {
                RationalBezierSurfaceDifferentialBounds.outerBoundaries(of: patch,
                    uDomain: .closed($0.uLower, $0.uUpper), vDomain: .closed($0.vLower, $0.vUpper))
            } ?? []
            let proof = try original.fields(over: BSplineSurfaceEmbeddingValidator.parameterBox(of: patch),
                stationary: stationaryBoundaries, admission: admission)
            self.differentialBounds = proof.0
            self.bounds = proof.1
        }
    }

    private static func parameterBox(of patch: RationalBezierSurfacePatch3D) throws -> SurfaceParameterBox {
        try SurfaceParameterBox(u: ScalarInterval(lower: patch.uLower, upper: patch.uUpper),
            v: ScalarInterval(lower: patch.vLower, upper: patch.vUpper))
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
        return try BSplineSurfaceBezierDecomposer()
            .surfacePatches(surface: surface, tolerance: tolerance, admission: admission)
            .compactMap { patch in
                let uLower = max(patch.uLower, bounds.uLower)
                let uUpper = min(patch.uUpper, bounds.uUpper)
                let vLower = max(patch.vLower, bounds.vLower)
                let vUpper = min(patch.vUpper, bounds.vUpper)
                guard uLower < uUpper, vLower < vUpper else {
                    return nil
                }
                return try patch.trimmed(
                    uFrom: uLower,
                    uTo: uUpper,
                    vFrom: vLower,
                    vTo: vUpper,
                    tolerance: tolerance, admission: admission
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
            if try projectionProvesInjective(bounds: [cells[index].differentialBounds]) {
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
            guard let unresolved = try firstUnresolvedTouchingRegion(in: cells, certifiedRegions: &certifiedRegions) else {
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
            var coarsestDepth = Int.max
            for index in unresolved { try admission.work(1); coarsestDepth = min(coarsestDepth, cells[index].depth) }
            try admission.storageElements(unresolved.count, of: Int.self)
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
                try admission.work(1)
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
        certifiedRegions: inout Set<RetainedBounds>) throws -> [Int]? {
        guard cells.count > 1 else { return nil }
        let slots = cells.count.multipliedReportingOverflow(by: 3)
        guard !slots.overflow else { throw GeometryConversionError.resourceLimitExceeded("Native touching-region storage overflows.") }
        try admission.storageElements(cells.count, of: RetainedBounds.self)
        try admission.storageElements(cells.count, of: RetainedBounds.self)
        try admission.storageElements(slots.partialValue, of: Int.self)
        let domains = cells.map { RetainedBounds(uLower: $0.patch.uLower, uUpper: $0.patch.uUpper,
            vLower: $0.patch.vLower, vUpper: $0.patch.vUpper) }
        let order = try domains.indices.sorted {
            try admission.work(1)
            return domains[$0].uLower == domains[$1].uLower ? $0 < $1 : domains[$0].uLower < domains[$1].uLower
        }
        var hulls = domains
        func build(_ lower: Int, _ upper: Int) throws -> RetainedBounds {
            try admission.work(1)
            let middle = (lower + upper) / 2
            var hull = domains[order[middle]]
            for range in [lower..<middle, (middle + 1)..<upper] where !range.isEmpty {
                let child = try build(range.lowerBound, range.upperBound)
                hull = RetainedBounds(uLower: min(hull.uLower, child.uLower),
                    uUpper: max(hull.uUpper, child.uUpper), vLower: min(hull.vLower, child.vLower),
                    vUpper: max(hull.vUpper, child.vUpper))
            }
            hulls[middle] = hull
            return hull
        }
        _ = try build(0, order.count)
        func candidates(_ region: RetainedBounds, strict: Bool) throws -> [Int] {
            func overlaps(_ bounds: RetainedBounds) -> Bool {
                let du = min(bounds.uUpper, region.uUpper) - max(bounds.uLower, region.uLower)
                let dv = min(bounds.vUpper, region.vUpper) - max(bounds.vLower, region.vLower)
                return strict ? du > 0 && dv > 0 : du >= 0 && dv >= 0
            }
            var result: [Int] = []
            func visit(_ lower: Int, _ upper: Int) throws {
                try admission.work(1)
                guard lower < upper else { return }
                let middle = (lower + upper) / 2
                guard overlaps(hulls[middle]) else { return }
                let index = order[middle]
                if overlaps(domains[index]) { try admission.storage(1); result.append(index) }
                try visit(lower, middle)
                try visit(middle + 1, upper)
            }
            try visit(0, order.count)
            return try result.sorted { try admission.work(1); return $0 < $1 }
        }
        for firstIndex in 0..<(cells.count - 1) {
            let first = domains[firstIndex]
            for secondIndex in try candidates(first, strict: false) where secondIndex > firstIndex {
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
                    regionIndexes = try candidates(region, strict: true)
                }
                try admission.storageElements(regionIndexes.count, of: RationalBezierSurfaceDifferentialBounds.self)
                let regionBounds = regionIndexes.map { cells[$0].differentialBounds }
                if try projectionProvesInjective(bounds: regionBounds) == false {
                    return regionIndexes
                }
                if certifiedRegions.count < maximumPairCellCount {
                    try admission.storageElements(2, of: RetainedBounds.self)
                    certifiedRegions.insert(region)
                }
            }
        }
        return nil
    }

    private func subdivide(
        indexes: [Int],
        cells: inout [Cell],
        tolerance: ModelingTolerance
    ) throws {
        let slots = indexes.count.multipliedReportingOverflow(by: 2)
        guard !slots.overflow else { throw GeometryConversionError.resourceLimitExceeded("Native subdivision index storage overflows.") }
        try admission.storage(slots.partialValue)
        let uniqueIndexes = try Array(Set(indexes)).sorted { try admission.work(1); return $0 > $1 }
        guard uniqueIndexes.isEmpty == false else {
            throw resourceLimit(
                residual: 0.0,
                tolerance: tolerance,
                message: "B-spline surface embedding found an empty unresolved region."
            )
        }
        for index in uniqueIndexes {
            try admission.work(1)
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
            try admission.storageElements(4, of: Cell.self)
            let children = try cell.patch.subdivided(admission: admission).map {
                try Cell(patch: $0, depth: cell.depth + 1, original: cell.original, stationaryDomain: cell.stationaryDomain, admission: admission)
            }
            cells.remove(at: index)
            cells.insert(contentsOf: children, at: index)
        }
    }

    private func projectionProvesInjective(
        bounds: [RationalBezierSurfaceDifferentialBounds]
    ) throws -> Bool {
        try admission.work(1)
        guard bounds.isEmpty == false else { return false }
        for axes in try projectionCandidates(from: bounds) {
            var firstSign: Int?
            var secondSign: Int?
            var determinantSign: Int?
            var isConsistent = true
            for bound in bounds {
                try admission.work(1)
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
    ) throws -> [ProjectionAxes] {
        let slots = bounds.count.addingReportingOverflow(7)
        guard !slots.overflow else { throw GeometryConversionError.resourceLimitExceeded("Native projection candidate storage overflows.") }
        try admission.storageElements(slots.partialValue, of: ProjectionAxes.self)
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
            try admission.work(1)
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
        try first.validate(tolerance: tolerance, consumeWork: { try admission.work(1) })
        try second.validate(tolerance: tolerance, consumeWork: { try admission.work(1) })
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
        let firstPatches = try BSplineSurfaceBezierDecomposer().surfacePatches(surface: first, tolerance: tolerance, admission: admission)
        let secondPatches = try BSplineSurfaceBezierDecomposer().surfacePatches(surface: second, tolerance: tolerance, admission: admission)
        guard !firstPatches.isEmpty, !secondPatches.isEmpty,
              firstPatches.count <= maximumCellCount, secondPatches.count <= maximumCellCount else {
            throw resourceLimit(residual: Double(max(firstPatches.count, secondPatches.count)), tolerance: tolerance,
                message: "Surface separation requires nonempty patch sets within the cell budget.")
        }
        func originals(_ source: BSplineSurface3D, _ patches: [RationalBezierSurfacePatch3D]) throws -> [NativeSurfaceOriginalCellChart] {
            guard case let .closed(u0, u1) = source.uDomain, case let .closed(v0, v1) = source.vDomain else {
                throw GeometryConversionError.invalidInput("Original chart separation requires finite native domains.")
            }
            let atlas = try NativeSurfaceOriginalAtlas(source: source, over: SurfaceParameterBox(
                    u: ScalarInterval(lower: u0, upper: u1), v: ScalarInterval(lower: v0, upper: v1)),
                maximumSpanCount: maximumCellCount, tolerance: tolerance, admission: admission)
            try admission.storageElements(patches.count, of: NativeSurfaceOriginalCellChart.self)
            return try patches.map { patch in
                let box = try Self.parameterBox(of: patch)
                return .init(law: try atlas.selected(over: box, admission: admission), nativeDomain: box, workingDomain: box)
            }
        }
        let firstOriginals = try originals(first, firstPatches), secondOriginals = try originals(second, secondPatches)
        try admission.storageElements(NativeSurfaceEmbeddingPreparationReservation.sum([firstPatches.count, secondPatches.count]),
            of: BoundingBox3D.self)
        let firstBounds = try firstPatches.indices.map { try firstOriginals[$0].positionBounds(
            over: Self.parameterBox(of: firstPatches[$0]), admission: admission) }
        let secondBounds = try secondPatches.indices.map { try secondOriginals[$0].positionBounds(
            over: Self.parameterBox(of: secondPatches[$0]), admission: admission) }
        var visited = 0
        for i in firstPatches.indices {
            for j in secondPatches.indices {
                try consumeSeparationCell(&visited, tolerance: tolerance)
                guard firstBounds[i].intersects(secondBounds[j], tolerance: tolerance.distance) else { continue }
                try certifyPairSeparation(first: firstPatches[i], second: secondPatches[j],
                    firstOriginal: firstOriginals[i], secondOriginal: secondOriginals[j],
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
        try first.validate(tolerance: tolerance, consumeWork: { try admission.work(1) })
        try second.validate(tolerance: tolerance, consumeWork: { try admission.work(1) })
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
        func halves(_ surface: BSplineSurface3D, _ sides: [SurfaceParameterBoundary]) throws -> [SurfaceParameterBox] {
            guard case let .closed(u0, u1) = surface.uDomain,
                  case let .closed(v0, v1) = surface.vDomain else {
                throw GeometryConversionError.invalidInput("Opposite-boundary admission requires finite original domains.")
            }
            // These authored subdivision stations only select original closed
            // subdomains; they never issue a new rounded surface source.
            let um = u0 * 0.5 + u1 * 0.5, vm = v0 * 0.5 + v1 * 0.5
            guard u0 < um, um < u1, v0 < vm, vm < v1 else {
                throw resourceLimit(residual: 0, tolerance: tolerance,
                    message: "Original opposite-boundary domains have no representable positive split.")
            }
            try admission.storageElements(sides.count, of: SurfaceParameterBox.self)
            return try sides.map { side in
                let u: ScalarInterval, v: ScalarInterval
                switch side {
                case .uLower: u = try .init(lower: u0, upper: um); v = try .init(lower: v0, upper: v1)
                case .uUpper: u = try .init(lower: um, upper: u1); v = try .init(lower: v0, upper: v1)
                case .vLower: u = try .init(lower: u0, upper: u1); v = try .init(lower: v0, upper: vm)
                case .vUpper: u = try .init(lower: u0, upper: u1); v = try .init(lower: vm, upper: v1)
                }
                return SurfaceParameterBox(u: u, v: v)
            }
        }
        let a = try halves(first, firstBoundaries), b = try halves(second, secondBoundaries)
        let proof = Self(maximumLocalSubdivisionDepth: maximumLocalSubdivisionDepth,
            maximumCellCount: maximumCellCount / 4, maximumPairSubdivisionDepth: maximumPairSubdivisionDepth,
            maximumPairCellCount: maximumPairCellCount / 4, admission: try admission.shifted(by: 1))
        for i in a.indices {
            for j in b.indices {
                if i == j {
                    try proof.validateAdjacentRegions(first: first, firstBoundary: firstBoundaries[i], firstRegion: a[i],
                        second: second, secondBoundary: secondBoundaries[j], secondRegion: b[j], tolerance: tolerance)
                } else {
                    try proof.validateOriginalRegionSeparation(first: first, firstRegion: a[i],
                        second: second, secondRegion: b[j], tolerance: tolerance)
                }
            }
        }
    }

    private func validateOriginalRegionSeparation(first: BSplineSurface3D, firstRegion: SurfaceParameterBox,
        second: BSplineSurface3D, secondRegion: SurfaceParameterBox, tolerance: ModelingTolerance) throws {
        func cells(_ source: BSplineSurface3D, _ region: SurfaceParameterBox) throws
            -> [(RationalBezierSurfacePatch3D, NativeSurfaceOriginalCellChart, BoundingBox3D)] {
            let atlas = try NativeSurfaceOriginalAtlas(source: source, over: region,
                maximumSpanCount: maximumCellCount, tolerance: tolerance, admission: admission)
            let patches = try clippedPatches(surface: source, bounds: RetainedBounds(
                uLower: region.u.lower, uUpper: region.u.upper, vLower: region.v.lower,
                vUpper: region.v.upper), tolerance: tolerance)
            guard !patches.isEmpty, patches.count <= maximumCellCount else {
                throw resourceLimit(residual: Double(patches.count), tolerance: tolerance,
                    message: "Original regional separation exhausted its native cell capacity.")
            }
            try admission.storageElements(patches.count,
                of: (RationalBezierSurfacePatch3D, NativeSurfaceOriginalCellChart, BoundingBox3D).self)
            return try patches.map { patch in
                let box = try Self.parameterBox(of: patch)
                let original = NativeSurfaceOriginalCellChart(law: try atlas.selected(over: box, admission: admission),
                    nativeDomain: box, workingDomain: box)
                return (patch, original, try original.positionBounds(over: box, admission: admission))
            }
        }
        let a = try cells(first, firstRegion), b = try cells(second, secondRegion)
        var visited = 0
        for first in a { for second in b {
            try consumeSeparationCell(&visited, tolerance: tolerance)
            if !first.2.intersects(second.2, tolerance: tolerance.distance) { continue }
            try certifyPairSeparation(first: first.0, second: second.0,
                firstOriginal: first.1, secondOriginal: second.1,
                visited: &visited, tolerance: tolerance, allowedCornerContacts: [])
        } }
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Loft single-edge admission retains a
    // clamped, shared native seam domain. Whole original polynomial equality
    // reconciles different degrees and knots, but general nonclamped or nonlinear
    // seam parameter correspondence remains outside this production path.
    public func validateAdjacent(
        first: BSplineSurface3D,
        firstBoundary: SurfaceParameterBoundary,
        second: BSplineSurface3D,
        secondBoundary: SurfaceParameterBoundary,
        tolerance: ModelingTolerance
    ) throws {
        try validateAdjacentRegions(first: first, firstBoundary: firstBoundary, firstRegion: nil,
            second: second, secondBoundary: secondBoundary, secondRegion: nil, tolerance: tolerance)
    }

    private func validateAdjacentRegions(first: BSplineSurface3D,
        firstBoundary: SurfaceParameterBoundary, firstRegion: SurfaceParameterBox?,
        second: BSplineSurface3D, secondBoundary: SurfaceParameterBoundary,
        secondRegion: SurfaceParameterBox?, tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try first.validate(tolerance: tolerance, consumeWork: { try admission.work(1) })
        try second.validate(tolerance: tolerance, consumeWork: { try admission.work(1) })
        guard maximumCellCount > 0, maximumLocalSubdivisionDepth >= 0,
              maximumPairSubdivisionDepth >= 0, maximumPairCellCount > 0 else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Adjacent surface admission requires a positive cell budget.")
        }
        var boundaryAllowance = AdjacentBoundaryAllowance(remaining: maximumPairCellCount,
            maximumDepth: maximumPairSubdivisionDepth, tolerance: tolerance, admission: admission)
        let issuer = OriginalSurfaceBoundarySourceIssuer()
        let originalFirstSeam = try issuer.boundary(of: .bSpline(first), at: firstBoundary,
            maximumDepth: maximumPairSubdivisionDepth, maximumSpanCount: maximumCellCount, tolerance: tolerance, usage: &boundaryAllowance)
        let originalSecondSeam = try issuer.boundary(of: .bSpline(second), at: secondBoundary,
            maximumDepth: maximumPairSubdivisionDepth, maximumSpanCount: maximumCellCount, tolerance: tolerance, usage: &boundaryAllowance)
        let reverseSecond: Bool
        if try OriginalSplineTraversalIdentity().proves(originalFirstSeam, originalSecondSeam,
            usage: &boundaryAllowance) { reverseSecond = false }
        else if try OriginalSplineTraversalIdentity().proves(originalFirstSeam,
            originalSecondSeam.reversed(), usage: &boundaryAllowance) { reverseSecond = true }
        else {
            throw resourceLimit(residual: 0, tolerance: tolerance,
                message: "Adjacent original spline boundaries do not share the same directed whole seam law.")
        }
        var originalContinuity = NativeSurfaceOriginalProofAllowance(admission: admission)
        try OriginalSplineSurfaceContinuityAdmission().validate(first, tolerance: tolerance, usage: &originalContinuity)
        try OriginalSplineSurfaceContinuityAdmission().validate(second, tolerance: tolerance, usage: &originalContinuity)
        if try originalAdjacentProjection(first: first, firstBoundary: firstBoundary,
            second: second, secondBoundary: secondBoundary, reverseSecond: reverseSecond,
            firstRegion: firstRegion, secondRegion: secondRegion, tolerance: tolerance) { return }
        func chart(_ source: BSplineSurface3D, boundary: SurfaceParameterBoundary,
                   atUpper: Bool) throws -> BSplineSurface3D {
            try admission.work(1)
            let count = try NativeSurfaceEmbeddingPreparationReservation.product([source.uControlPointCount, source.vControlPointCount])
            try admission.storage(NativeSurfaceEmbeddingPreparationReservation.sum([
                NativeSurfaceEmbeddingPreparationReservation.product([count, 12]),
                NativeSurfaceEmbeddingPreparationReservation.product([
                    NativeSurfaceEmbeddingPreparationReservation.sum([source.uControlPointCount, source.vControlPointCount]), 9]),
                source.uKnots.count, source.vKnots.count]))
            try admission.work(NativeSurfaceEmbeddingPreparationReservation.product([count, 6]))
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
        let a = try chart(first, boundary: firstBoundary, atUpper: true)
        var b = try chart(second, boundary: secondBoundary, atUpper: false)
        if reverseSecond {
            let sum = b.uKnots[0] + b.uKnots[b.uKnots.count - 1]
            try admission.storage(b.uKnots.count)
            try admission.work(b.uKnots.count)
            let count = try NativeSurfaceEmbeddingPreparationReservation.product([b.uControlPointCount, b.vControlPointCount, 2])
            try admission.storage(count); try admission.work(count)
            b = BSplineSurface3D(uDegree: b.uDegree, vDegree: b.vDegree,
                uKnots: b.uKnots.reversed().map { sum - $0 }, vKnots: b.vKnots,
                controlPoints: b.controlPoints.map { Array($0.reversed()) },
                weights: b.weights.map { Array($0.reversed()) })
        }
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
                maximumPairCellCount: maximumPairCellCount / 2, admission: admission)
            for index in 0..<2 {
                let surface = index == 0 ? first : second
                let region = index == 0 ? firstRegion : secondRegion
                try local.validate(surface, uDomain: region.map { .closed($0.u.lower, $0.u.upper) } ?? surface.uDomain,
                    vDomain: region.map { .closed($0.v.lower, $0.v.upper) } ?? surface.vDomain,
                    tolerance: tolerance, allowStationaryBoundaryParameterization: true)
            }
            return
        }
        guard clamped(a), clamped(b) else {
            throw resourceLimit(residual: 0, tolerance: tolerance,
                message: "Adjacent spline charts require clamped nominated boundaries.")
        }
        // Working free stations must retain the exact original traversal. Rounded
        // candidate transverse labels only schedule a continuous per-owner chart.
        guard a.uDomain == b.uDomain,
              try exactFreeScheduling(source: first, boundary: firstBoundary, candidate: a,
                reversed: false, usage: &boundaryAllowance),
              try exactFreeScheduling(source: second, boundary: secondBoundary, candidate: b,
                reversed: reverseSecond, usage: &boundaryAllowance) else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): The original global projection
            // route above covers normalized unequal free domains. Loft's local
            // touching-cell continuation still needs exact nonrepresentable
            // shared seam cuts before it can publish those other original charts.
            throw resourceLimit(residual: 0, tolerance: tolerance,
                message: "Adjacent local subdivision requires exact original free-axis scheduling stations.")
        }
        guard boundaryAllowance.remaining > 0 else {
            throw resourceLimit(residual: Double(maximumPairCellCount), tolerance: tolerance,
                message: "Original seam algebra exhausted the adjacent pair allowance.")
        }
        let continuation = Self(maximumLocalSubdivisionDepth: maximumLocalSubdivisionDepth,
            maximumCellCount: maximumCellCount, maximumPairSubdivisionDepth: maximumPairSubdivisionDepth,
            maximumPairCellCount: boundaryAllowance.remaining, admission: admission)
        var cells: [Cell] = []
        for index in 0..<2 {
            let raw = index == 0 ? first : second
            let boundary = index == 0 ? firstBoundary : secondBoundary
            let rawRegion = index == 0 ? firstRegion : secondRegion
            let swapsAxes = boundary == .uLower || boundary == .uUpper
            let reverseV = (boundary == .uUpper || boundary == .vUpper) != (index == 0)
            let reverseU = index == 1 && reverseSecond
            guard case let .closed(rawU0, rawU1) = raw.uDomain,
                  case let .closed(rawV0, rawV1) = raw.vDomain else {
                throw GeometryConversionError.invalidInput("Original adjacent chart domains must remain finite.")
            }
            let whole = try rawRegion ?? SurfaceParameterBox(u: try ScalarInterval(lower: rawU0, upper: rawU1),
                v: try ScalarInterval(lower: rawV0, upper: rawV1))
            let atlas = try NativeSurfaceOriginalAtlas(source: raw, over: whole,
                maximumSpanCount: maximumCellCount, tolerance: tolerance, admission: admission)
            let patches = try clippedPatches(surface: raw,
                bounds: RetainedBounds(uLower: whole.u.lower, uUpper: whole.u.upper,
                    vLower: whole.v.lower, vUpper: whole.v.upper), tolerance: tolerance)
            guard !patches.isEmpty, patches.count <= maximumCellCount - cells.count else {
                throw resourceLimit(residual: Double(patches.count), tolerance: tolerance,
                    message: "Adjacent original charts exhausted the cell capacity.")
            }
            let transverse = swapsAxes ? whole.u : whole.v
            let knots = swapsAxes ? raw.uKnots : raw.vKnots
            try admission.storage(NativeSurfaceEmbeddingPreparationReservation.sum([knots.count, 2]))
            var cuts = [transverse.lower]
            for knot in knots {
                try admission.work(1)
                if knot > transverse.lower, knot < transverse.upper, cuts.last != knot { cuts.append(knot) }
            }
            cuts.append(transverse.upper)
            let intervalCount = cuts.count - 1
            let freeKnots = swapsAxes ? raw.vKnots : raw.uKnots
            let freeSum = freeKnots[0] + freeKnots[freeKnots.count - 1]
            let freeWhole = swapsAxes ? whole.v : whole.u
            let freeLower = reverseU ? freeSum - freeWhole.upper : freeWhole.lower
            let freeUpper = reverseU ? freeSum - freeWhole.lower : freeWhole.upper
            let stationaryDomain = RetainedBounds(uLower: freeLower, uUpper: freeUpper,
                vLower: Double(index), vUpper: Double(index + 1))
            let originalCellStart = cells.count
            try admission.storageElements(patches.count, of: Cell.self)
            for patch in patches {
                let nativeBox = try Self.parameterBox(of: patch)
                let law = try atlas.selected(over: nativeBox, admission: admission)
                let nativeTransverse = swapsAxes ? nativeBox.u : nativeBox.v
                var ordinal: Int?
                for i in 0..<intervalCount {
                    try admission.work(1)
                    if cuts[i] == nativeTransverse.lower, cuts[i + 1] == nativeTransverse.upper { ordinal = i; break }
                }
                guard let ordinal else {
                    throw GeometryConversionError.invalidInput("Original adjacent owner escaped its transverse partition.")
                }
                let ordered = reverseV ? intervalCount - 1 - ordinal : ordinal
                let workingLower = Double(index) + Double(ordered) / Double(intervalCount)
                let workingUpper = Double(index) + Double(ordered + 1) / Double(intervalCount)
                guard workingLower < workingUpper else {
                    throw GeometryConversionError.resourceLimitExceeded("Original adjacent scheduling has no distinct owner labels.")
                }
                let nativeFree = swapsAxes ? nativeBox.v : nativeBox.u
                let workingU0 = reverseU ? freeSum - nativeFree.upper : nativeFree.lower
                let workingU1 = reverseU ? freeSum - nativeFree.lower : nativeFree.upper
                let netCount = try NativeSurfaceEmbeddingPreparationReservation.product(
                    [patch.controlPoints.count, patch.controlPoints[0].count])
                try admission.storage(NativeSurfaceEmbeddingPreparationReservation.sum([
                    NativeSurfaceEmbeddingPreparationReservation.product([netCount, 12]),
                    NativeSurfaceEmbeddingPreparationReservation.product([
                        NativeSurfaceEmbeddingPreparationReservation.sum([patch.controlPoints.count, patch.controlPoints[0].count]), 9])]))
                try admission.work(NativeSurfaceEmbeddingPreparationReservation.product([netCount, 6]))
                func oriented<T>(_ original: [[T]]) -> [[T]] {
                    var result = swapsAxes ? original[0].indices.map { i in original.map { $0[i] } } : original
                    if reverseV { result = Array(result.reversed()) }
                    if reverseU { result = result.map { Array($0.reversed()) } }
                    return result
                }
                let mapped = RationalBezierSurfacePatch3D(controlPoints: oriented(patch.controlPoints),
                    weights: oriented(patch.weights), uLower: workingU0, uUpper: workingU1,
                    vLower: workingLower, vUpper: workingUpper)
                let workingBox = try Self.parameterBox(of: mapped)
                cells.append(try Cell(patch: mapped, depth: 0,
                    original: .init(law: law, nativeDomain: nativeBox, workingDomain: workingBox,
                        swapsAxes: swapsAxes, reversesU: reverseU, reversesV: reverseV),
                    stationaryDomain: stationaryDomain, admission: admission))
            }
            for law in atlas.laws {
                try admission.work(1)
                let loU = max(law.native.uBounds.lower, whole.u.lower), hiU = min(law.native.uBounds.upper, whole.u.upper)
                let loV = max(law.native.vBounds.lower, whole.v.lower), hiV = min(law.native.vBounds.upper, whole.v.upper)
                if loU >= hiU || loV >= hiV { continue }
                var covered = false
                for cellIndex in originalCellStart..<cells.count {
                    try admission.work(1)
                    let owner = cells[cellIndex].original.law.native
                    if owner.uSpanIndex == law.native.uSpanIndex, owner.vSpanIndex == law.native.vSpanIndex,
                       owner.uCycle == law.native.uCycle, owner.vCycle == law.native.vCycle { covered = true; break }
                }
                guard covered else {
                    throw GeometryConversionError.invalidInput("Adjacent decomposition omitted a positive original native owner.")
                }
            }
        }
        if try projectionProvesInjective(bounds: cells.map(\.differentialBounds)) { return }
        try admission.storage(cells.count)
        let originalCharts = cells.map(\.original)
        func sourceStation(_ u: Double, _ v: Double) throws -> (BSplineSurface3D, Double, Double) {
            let query = try SurfaceParameterBox(u: ScalarInterval(lower: u, upper: u),
                v: ScalarInterval(lower: v, upper: v))
            for original in originalCharts {
                try admission.work(1)
                if u >= original.workingDomain.u.lower, u <= original.workingDomain.u.upper,
                   v >= original.workingDomain.v.lower, v <= original.workingDomain.v.upper {
                    let native = try original.nativeBox(over: query)
                    // These stations only propose rejection witnesses or axes;
                    // positive authority remains the whole original interval fields.
                    return (original.law.source, native.u.midpoint, native.v.midpoint)
                }
            }
            throw GeometryConversionError.invalidInput("Adjacent candidate station has no original source chart.")
        }
        func point(_ u: Double, _ v: Double) throws -> Point3D {
            let (surface, nativeU, nativeV) = try sourceStation(u, v)
            try NativeSurfaceEmbeddingPreparationReservation.point(surface, admission: admission)
            return try surface.point(u: nativeU, v: nativeV, tolerance: tolerance)
        }
        var comparisons = 0
        for i in cells.indices {
            for j in cells.indices where j > i {
                try continuation.consumeSeparationCell(&comparisons, tolerance: tolerance)
                try rejectSampledCoincidence(first: cells[i].patch, second: cells[j].patch,
                    point: point, tolerance: tolerance)
            }
        }
        try continuation.certifyLocalInjectivity(cells: &cells, normalAt: { u, v in
            let (surface, nativeU, nativeV) = try sourceStation(u, v)
            try NativeSurfaceEmbeddingPreparationReservation.point(surface, admission: admission)
            return try surface.normal(u: nativeU, v: nativeV, tolerance: tolerance)
        }, tolerance: tolerance)
        guard comparisons < boundaryAllowance.remaining else {
            throw resourceLimit(residual: Double(comparisons), tolerance: tolerance,
                message: "Adjacent chart comparisons exhausted the remaining original proof allowance.")
        }
        let separation = Self(maximumLocalSubdivisionDepth: maximumLocalSubdivisionDepth,
            maximumCellCount: maximumCellCount, maximumPairSubdivisionDepth: maximumPairSubdivisionDepth,
            maximumPairCellCount: boundaryAllowance.remaining - comparisons, admission: admission)
        try separation.certifySeparatedCells(cells, point: point, tolerance: tolerance)
    }

    private struct AdjacentBoundaryAllowance: RationalAlgebraAdmitting {
        var remaining: Int
        let maximumDepth: Int
        let tolerance: ModelingTolerance
        let admission: NativeSurfaceEmbeddingAdmission

        mutating func consumeExactWork(_ count: Int) throws {
            try Task.checkCancellation()
            guard count >= 0, count <= remaining else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                    message: "Original seam equality exhausted the cumulative adjacent pair allowance.")
            }
            try admission.work(count)
            remaining -= count
        }
        mutating func retainExactStorage(_ count: Int) throws {
            guard count >= 0, count <= remaining else {
                throw GeometryConversionError.resourceLimitExceeded("Native adjacent source storage exhausted its original limit.")
            }
            try admission.storageWords(count); remaining -= count
        }
        mutating func visitExactCell(depth: Int) throws {
            guard depth >= 0, depth <= maximumDepth else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                    message: "Original seam equality exceeded the adjacent proof depth.")
            }
            try admission.cell(depth: depth)
            guard remaining > 0 else { throw GeometryConversionError.resourceLimitExceeded("Native adjacent source cell limit exhausted.") }
            remaining -= 1
        }
    }

    private func exactFreeScheduling(source: BSplineSurface3D, boundary: SurfaceParameterBoundary,
        candidate: BSplineSurface3D, reversed: Bool, usage: inout AdjacentBoundaryAllowance) throws -> Bool {
        let original = boundary == .uLower || boundary == .uUpper ? source.vKnots : source.uKnots
        guard candidate.uKnots.count == original.count else { return false }
        let first = try ExactRationalCoefficient.originalDouble(original[0], usage: &usage)
        let last = try ExactRationalCoefficient.originalDouble(original[original.count - 1], usage: &usage)
        let sum = try first.adding(last, usage: &usage)
        for index in original.indices {
            let raw = try ExactRationalCoefficient.originalDouble(original[reversed ? original.count - 1 - index : index], usage: &usage)
            let expected = reversed ? try sum.subtracting(raw, usage: &usage) : raw
            if expected != (try ExactRationalCoefficient.originalDouble(candidate.uKnots[index], usage: &usage)) { return false }
        }
        return true
    }

    private func originalAdjacentProjection(first: BSplineSurface3D, firstBoundary: SurfaceParameterBoundary,
        second: BSplineSurface3D, secondBoundary: SurfaceParameterBoundary, reverseSecond: Bool,
        firstRegion: SurfaceParameterBox? = nil, secondRegion: SurfaceParameterBox? = nil,
        tolerance: ModelingTolerance) throws -> Bool {
        var fields: [RationalBezierSurfaceDifferentialBounds] = []
        for index in 0..<2 {
            let source = index == 0 ? first : second
            let boundary = index == 0 ? firstBoundary : secondBoundary
            guard case let .closed(u0, u1) = source.uDomain,
                  case let .closed(v0, v1) = source.vDomain else {
                throw GeometryConversionError.invalidInput("Original adjacency requires finite original chart domains.")
            }
            let whole = try (index == 0 ? firstRegion : secondRegion)
                ?? SurfaceParameterBox(u: try ScalarInterval(lower: u0, upper: u1),
                    v: try ScalarInterval(lower: v0, upper: v1))
            let atlas = try NativeSurfaceOriginalAtlas(source: source, over: whole,
                maximumSpanCount: maximumCellCount, tolerance: tolerance, admission: admission)
            guard atlas.laws.count <= maximumCellCount - fields.count else {
                throw resourceLimit(residual: Double(atlas.laws.count), tolerance: tolerance,
                    message: "Original adjacent projection exhausted its cumulative native owner capacity.")
            }
            try admission.storageElements(atlas.laws.count, of: RationalBezierSurfaceDifferentialBounds.self)
            for law in atlas.laws {
                try admission.cell(depth: 0)
                let loU = max(law.native.uBounds.lower, whole.u.lower)
                let hiU = min(law.native.uBounds.upper, whole.u.upper)
                let loV = max(law.native.vBounds.lower, whole.v.lower)
                let hiV = min(law.native.vBounds.upper, whole.v.upper)
                guard loU < hiU, loV < hiV else { continue }
                let box = try SurfaceParameterBox(u: ScalarInterval(lower: loU, upper: hiU),
                    v: ScalarInterval(lower: loV, upper: hiV))
                var stationary: Set<SurfaceParameterBoundary> = []
                try admission.storage(4)
                if box.u.lower == u0 { stationary.insert(.uLower) }
                if box.u.upper == u1 { stationary.insert(.uUpper) }
                if box.v.lower == v0 { stationary.insert(.vLower) }
                if box.v.upper == v1 { stationary.insert(.vUpper) }
                let chart = NativeSurfaceOriginalCellChart(law: law, nativeDomain: whole,
                    workingDomain: SurfaceParameterBox(u: try ScalarInterval(lower: 0, upper: 1),
                        v: try ScalarInterval(lower: Double(index), upper: Double(index + 1))),
                    swapsAxes: boundary == .uLower || boundary == .uUpper,
                    reversesU: index == 1 && reverseSecond,
                    reversesV: (boundary == .uUpper || boundary == .vUpper) != (index == 0))
                fields.append(try chart.fields(overNative: box, nativeStationary: stationary, admission: admission).0)
            }
        }
        return try projectionProvesInjective(bounds: fields)
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
            let firstSign = try sign(pa), secondSign = try sign(pb)
            let side = firstSign == .zero
                ? (secondSign == .positive ? RobustSign.negative : RobustSign.positive) : firstSign
            guard side == .positive || side == .negative else { return false }
            let opposite: RobustSign = side == .positive ? .negative : .positive
            var firstStrict = true, secondStrict = true
            let firstSeparated = try a.controlPoints.dropLast().allSatisfy { row in
                try row.allSatisfy {
                    let value = try sign($0)
                    if value == .zero { firstStrict = false }
                    return value == side || value == .zero
                }
            }
            let secondSeparated = try b.controlPoints.dropFirst().allSatisfy { row in
                try row.allSatisfy {
                    let value = try sign($0)
                    if value == .zero { secondStrict = false }
                    return value == opposite || value == .zero
                }
            }
            // Strictness on either chart confines its contact with the plane
            // to the shared seam; weak separation suffices for the other chart.
            if firstSeparated && secondSeparated && (firstStrict || secondStrict) { return true }
        }
        return false
    }

    private func consumeSeparationCell(_ visited: inout Int, tolerance: ModelingTolerance, depth: Int = 0) throws {
        guard visited < maximumPairCellCount else {
            throw resourceLimit(residual: Double(visited), tolerance: tolerance,
                message: "B-spline surface separation exhausted its pair cell budget.")
        }
        try admission.cell(depth: depth)
        visited += 1
    }

    private func certifyPairSeparation(
        first: RationalBezierSurfacePatch3D, second: RationalBezierSurfacePatch3D,
        firstOriginal: NativeSurfaceOriginalCellChart, secondOriginal: NativeSurfaceOriginalCellChart,
        visited: inout Int, tolerance: ModelingTolerance,
        allowedCornerContacts: [(first: Point2D, second: Point2D)] = [],
        initialDepth: Int = 0
    ) throws {
        let causalAdmission = try admission.shifted(by: initialDepth)
        try causalAdmission.storageElements(1, of: PairCell.self)
        let firstNet = try NativeSurfaceOriginalCoefficientNet(chart: firstOriginal,
            over: Self.parameterBox(of: first), admission: causalAdmission)
        let secondNet = try NativeSurfaceOriginalCoefficientNet(chart: secondOriginal,
            over: Self.parameterBox(of: second), admission: causalAdmission)
        var pending = [PairCell(difference: try RationalBezierSurfaceSurfaceDifferencePatch(
            originalFirst: firstNet, originalSecond: secondNet, tolerance: tolerance, admission: causalAdmission), depth: 0)]
        while let pair = pending.popLast() {
            if pair.depth > 0 { try consumeSeparationCell(&visited, tolerance: tolerance, depth: try NativeSurfaceEmbeddingPreparationReservation.sum([initialDepth, pair.depth])) }
            if try pair.difference.excludesZero(admission: causalAdmission) { continue }
            if try pair.difference.excludesZeroAlongSurfaceDirections(allowedCornerContacts: allowedCornerContacts, admission: causalAdmission) { continue }
            guard pair.depth < maximumPairSubdivisionDepth else {
                throw resourceLimit(residual: Double(pair.depth), tolerance: tolerance,
                    message: "B-spline surface separation could not exclude intersection within the subdivision limit.")
            }
            let parameterIndex = widestParameterIndex(pair.difference)
            try causalAdmission.storageElements(2, of: PairCell.self)
            pending.append(contentsOf: try pair.difference.subdivided(parameterIndex: parameterIndex, admission: causalAdmission)
                .map { PairCell(difference: $0, depth: pair.depth + 1) })
        }
    }

    private func certifySeparatedCells(
        _ cells: [Cell],
        point: (Double, Double) throws -> Point3D,
        tolerance: ModelingTolerance
    ) throws {
        guard cells.count > 1 else { return }
        if try projectionProvesInjective(bounds: cells.map(\.differentialBounds)) { return }
        let axes: [KeyPath<Point3D, Double>] = [\.x, \.y, \.z]
        var axis = axes[0]
        var bestScore = Double.infinity
        for candidate in axes {
            var lower = Double.infinity, upper = -Double.infinity, width = 0.0
            for cell in cells {
                try admission.work(1)
                let minimum = cell.bounds.minimum[keyPath: candidate]
                let maximum = cell.bounds.maximum[keyPath: candidate]
                lower = min(lower, minimum)
                upper = max(upper, maximum)
                width += maximum - minimum
            }
            let score = upper > lower ? width / (upper - lower) : .infinity
            if score < bestScore { axis = candidate; bestScore = score }
        }
        try admission.storage(cells.count)
        let ordered = try cells.indices.sorted {
            try admission.work(1)
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
                try consumeSeparationCell(&visitedPairCells, tolerance: tolerance, depth: max(cells[firstIndex].depth, cells[secondIndex].depth))
                let first = cells[firstIndex].patch
                let second = cells[secondIndex].patch
                guard touches(first, second) == false else { continue }
                guard cells[firstIndex].bounds.intersects(cells[secondIndex].bounds,
                    tolerance: tolerance.distance) else { continue }
                try rejectSampledCoincidence(
                    first: first,
                    second: second,
                    point: point,
                    tolerance: tolerance
                )
                try certifyPairSeparation(first: first, second: second,
                    firstOriginal: cells[firstIndex].original, secondOriginal: cells[secondIndex].original,
                    visited: &visitedPairCells, tolerance: tolerance,
                    initialDepth: max(cells[firstIndex].depth, cells[secondIndex].depth))
            }
        }
    }

    private func rejectSampledCoincidence(
        first: RationalBezierSurfacePatch3D,
        second: RationalBezierSurfacePatch3D,
        point: (Double, Double) throws -> Point3D,
        tolerance: ModelingTolerance
    ) throws {
        let fractions = [0.0, 0.5, 1.0]
        for firstU in fractions {
            for firstV in fractions {
                try admission.work(1)
                let firstParameter = parameter(
                    in: first,
                    uFraction: firstU,
                    vFraction: firstV
                )
                let firstPoint = try point(firstParameter.x, firstParameter.y)
                for secondU in fractions {
                    for secondV in fractions {
                        try admission.work(1)
                        let secondParameter = parameter(
                            in: second,
                            uFraction: secondU,
                            vFraction: secondV
                        )
                        if firstParameter == secondParameter { continue }
                        let secondPoint = try point(secondParameter.x, secondParameter.y)
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
