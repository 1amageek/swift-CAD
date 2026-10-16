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

    public func validateSeparation(first: BSplineSurface3D, second: BSplineSurface3D,
        tolerance: ModelingTolerance, allowedCornerContacts: [(first: Point2D, second: Point2D)] = []) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validateSeparation(first: first, second: second, tolerance: tolerance,
            allowedCornerContacts: allowedCornerContacts, using: &execution)
    }
    public func validateOppositeBoundaryContacts(first: BSplineSurface3D,
        firstBoundaries: [SurfaceParameterBoundary], second: BSplineSurface3D,
        secondBoundaries: [SurfaceParameterBoundary], tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validateOppositeBoundaryContacts(first: first, firstBoundaries: firstBoundaries,
            second: second, secondBoundaries: secondBoundaries, tolerance: tolerance, using: &execution)
    }
    public func validateAdjacent(first: BSplineSurface3D, firstBoundary: SurfaceParameterBoundary,
        second: BSplineSurface3D, secondBoundary: SurfaceParameterBoundary, tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validateAdjacent(first: first, firstBoundary: firstBoundary,
            second: second, secondBoundary: secondBoundary, tolerance: tolerance, using: &execution)
    }

    package static func stationaryPlanarSupport(for surface: BSplineSurface3D,
        tolerance: ModelingTolerance) throws -> Plane3D? {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try stationaryPlanarSupport(for: surface, tolerance: tolerance, using: &execution)
    }
    public func validate(_ surface: BSplineSurface3D, uDomain: ParameterDomain,
        vDomain: ParameterDomain, tolerance: ModelingTolerance,
        allowStationaryBoundaryParameterization: Bool = false) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(surface, uDomain: uDomain, vDomain: vDomain, tolerance: tolerance,
            allowStationaryBoundaryParameterization: allowStationaryBoundaryParameterization, using: &execution)
    }

    package static func stationaryPlanarSupport(
        for surface: BSplineSurface3D, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> Plane3D? {
        try surface.validate(tolerance: tolerance, using: &execution)
        guard surface.uDegree == 1, surface.vDegree == 1,
              surface.controlPoints.count == 2, surface.controlPoints[0].count == 2,
              surface.uKnots.count == 4, surface.vKnots.count == 4,
              surface.uKnots[0] == surface.uKnots[1], surface.uKnots[2] == surface.uKnots[3],
              surface.vKnots[0] == surface.vKnots[1], surface.vKnots[2] == surface.vKnots[3],
              surface.weights.allSatisfy({ $0.allSatisfy { $0 == 1 } }),
              surface.controlPoints[0].count == 2 else { return nil }
        // The selected resolver branch scans the fixed four-control joined net
        // in at most five passes; it creates no source-equivalence receipt.
        try execution.consumeWork(20)
        guard let plane = try DefaultPlanarSurfaceResolver().exactPlane(for: .bSpline(surface), tolerance: tolerance) else { return nil }
        try OriginalCoefficientAllocation.reserve(count: 4, of: Point3D.self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: 4, of: Point3D.self, using: &execution)
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
                determinantTolerance: 0, using: &execution)
            if sign == .zero { zeroCount += 1; continue }
            guard sign == .positive || sign == .negative else { return nil }
            if let orientation, sign != orientation { return nil }
            orientation = sign
            noncollinearIndex = i
        }
        guard zeroCount == 1, orientation != nil else { return nil }
        let i = noncollinearIndex
        guard try RobustPredicates.orientation3D(points[i], points[(i + 1) % 4],
            points[(i + 2) % 4], relativeTo: points[(i + 3) % 4], determinantTolerance: 0, using: &execution) == .zero
        else { return nil }
        try execution.checkpoint()
        return Plane3D(origin: plane.origin, normal: plane.normal)
    }

    public func validate(
        _ surface: BSplineSurface3D,
        uDomain: ParameterDomain,
        vDomain: ParameterDomain,
        tolerance: ModelingTolerance,
        allowStationaryBoundaryParameterization: Bool = false,
    using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        try tolerance.validate()
        try surface.validate(tolerance: tolerance, using: &execution)
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
        try OriginalSplineSurfaceContinuityAdmission().validate(surface, tolerance: tolerance, usage: &execution)
        let bounds = try retainedBounds(
            surface: surface,
            uDomain: uDomain,
            vDomain: vDomain,
            tolerance: tolerance,
        using: &execution)
        if allowStationaryBoundaryParameterization,
           uDomain == surface.uDomain, vDomain == surface.vDomain,
           try Self.stationaryPlanarSupport(for: surface, tolerance: tolerance, using: &execution) != nil {
            try execution.checkpoint(); return
        }
        let patches = try clippedPatches(
            surface: surface,
            bounds: bounds,
            tolerance: tolerance,
        using: &execution)
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
            maximumSpanCount: maximumCellCount, tolerance: tolerance, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: patches.count, of: Cell.self, using: &execution)
        var cells = try patches.map { patch in
            let box = try Self.parameterBox(of: patch)
            let law = try atlas.selected(over: box, using: &execution)
            return try Cell(patch: patch, depth: 0,
                original: .init(law: law, nativeDomain: box, workingDomain: box),
            stationaryDomain: allowStationaryBoundaryParameterization ? bounds : nil, using: &execution) }

        try certifyLocalInjectivity(
            cells: &cells,
            normalAt: { u, v, execution in
                try surface.normal(u: u, v: v, tolerance: tolerance, using: &execution)
            },
            tolerance: tolerance,
        using: &execution)
        try certifySeparatedCells(
            cells,
            point: { u, v, execution in
                try surface.point(u: u, v: v, tolerance: tolerance, using: &execution)
            },
            tolerance: tolerance,
        using: &execution)
            try execution.checkpoint()
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
            using execution: inout OriginalQueryExecution) throws {
            try execution.visitGeometricCell(depth: depth)
                        try OriginalCoefficientAllocation.reserve(count: 8, of: SurfaceParameterBoundary.self, using: &execution)
            self.patch = patch
            self.original = original
            self.depth = depth
            self.stationaryDomain = stationaryDomain
            self.stationaryBoundaries = stationaryDomain.map {
                RationalBezierSurfaceDifferentialBounds.outerBoundaries(of: patch,
                    uDomain: .closed($0.uLower, $0.uUpper), vDomain: .closed($0.vLower, $0.vUpper))
            } ?? []
            let proof = try original.fields(over: BSplineSurfaceEmbeddingValidator.parameterBox(of: patch),
                stationary: stationaryBoundaries, using: &execution)
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
        tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> RetainedBounds {
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
        tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> [RationalBezierSurfacePatch3D] {
        let source = try BSplineSurfaceBezierDecomposer()
            .surfacePatches(surface: surface, tolerance: tolerance, using: &execution)

        try OriginalCoefficientAllocation.reserve(count: source.count, of: RationalBezierSurfacePatch3D.self, using: &execution)
        var result: [RationalBezierSurfacePatch3D] = []; result.reserveCapacity(source.count)
        for patch in source {
                try execution.consumeWork(1)
                let uLower = max(patch.uLower, bounds.uLower)
                let uUpper = min(patch.uUpper, bounds.uUpper)
                let vLower = max(patch.vLower, bounds.vLower)
                let vUpper = min(patch.vUpper, bounds.vUpper)
                guard uLower < uUpper, vLower < vUpper else {
                    continue
                }
                result.append(try patch.trimmed(
                    uFrom: uLower,
                    uTo: uUpper,
                    vFrom: vLower,
                    vTo: vUpper,
                    tolerance: tolerance, using: &execution
                ))
            }
        return result
    }

    private func certifyLocalInjectivity(
        cells: inout [Cell],
        normalAt: (Double, Double, inout OriginalQueryExecution) throws -> Vector3D,
        tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws {
        var index = 0
        while index < cells.count {
            guard cells.count <= maximumCellCount else {
                throw resourceLimit(
                    residual: Double(cells.count),
                    tolerance: tolerance,
                    message: "B-spline surface embedding exhausted its local cell budget."
                )
            }
            if try projectionProvesInjective(bounds: OriginalCoefficientAllocation.singleton(cells[index].differentialBounds, using: &execution), using: &execution) {
                index += 1
            } else {
                try rejectSampledSingularity(
                    in: cells[index].patch,
                    normalAt: normalAt,
                    tolerance: tolerance,
                    stationaryBoundaries: cells[index].stationaryBoundaries,
                using: &execution)
                try subdivide(
                    indexes: [index],
                    cells: &cells,
                    tolerance: tolerance,
                using: &execution)
            }
        }
        // Restriction preserves the local injectivity proved above. Refining a
        // touching region does not invalidate proofs for the unchanged cells.
        var certifiedRegions: Set<RetainedBounds> = []
        var certifiedCapacity = 0
        while true {
            guard cells.count <= maximumCellCount else {
                throw resourceLimit(residual: Double(cells.count), tolerance: tolerance,
                    message: "B-spline surface embedding exhausted its local cell budget.")
            }
            guard let unresolved = try firstUnresolvedTouchingRegion(in: cells, certifiedRegions: &certifiedRegions, certifiedCapacity: &certifiedCapacity, using: &execution) else {
                return
            }
            for index in unresolved {
                try rejectSampledSingularity(
                    in: cells[index].patch,
                    normalAt: normalAt,
                    tolerance: tolerance,
                    stationaryBoundaries: cells[index].stationaryBoundaries,
                using: &execution)
            }
            var coarsestDepth = Int.max
            for index in unresolved { try execution.consumeWork(1); coarsestDepth = min(coarsestDepth, cells[index].depth) }
            try OriginalCoefficientAllocation.reserve(count: unresolved.count, of: Int.self, using: &execution)
            try subdivide(
                indexes: unresolved.filter { cells[$0].depth == coarsestDepth },
                cells: &cells,
                tolerance: tolerance,
            using: &execution)
        }
    }

    private func rejectSampledSingularity(
        in patch: RationalBezierSurfacePatch3D,
        normalAt: (Double, Double, inout OriginalQueryExecution) throws -> Vector3D,
        tolerance: ModelingTolerance,
        stationaryBoundaries: Set<SurfaceParameterBoundary>,
    using execution: inout OriginalQueryExecution) throws {
        for uFraction in [0.0, 0.5, 1.0] {
            for vFraction in [0.0, 0.5, 1.0] {
                if (uFraction == 0 && stationaryBoundaries.contains(.uLower))
                    || (uFraction == 1 && stationaryBoundaries.contains(.uUpper))
                    || (vFraction == 0 && stationaryBoundaries.contains(.vLower))
                    || (vFraction == 1 && stationaryBoundaries.contains(.vUpper)) { continue }
                try execution.consumeWork(1)
                let sample = parameter(
                    in: patch,
                    uFraction: uFraction,
                    vFraction: vFraction
                )
                do {
                    _ = try normalAt(sample.x, sample.y, &execution)
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
        certifiedRegions: inout Set<RetainedBounds>, certifiedCapacity: inout Int,
        using execution: inout OriginalQueryExecution) throws -> [Int]? {
        guard cells.count > 1 else { return nil }
        let slots = cells.count.multipliedReportingOverflow(by: 3)
        guard !slots.overflow else { throw GeometryConversionError.resourceLimitExceeded("Native touching-region storage overflows.") }
        try OriginalCoefficientAllocation.reserve(count: cells.count, of: RetainedBounds.self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: cells.count, of: RetainedBounds.self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: slots.partialValue, of: Int.self, using: &execution)
        let domains = cells.map { RetainedBounds(uLower: $0.patch.uLower, uUpper: $0.patch.uUpper,
            vLower: $0.patch.vLower, vUpper: $0.patch.vUpper) }
        let order = try domains.indices.sorted {
            try execution.consumeWork(1)
            return domains[$0].uLower == domains[$1].uLower ? $0 < $1 : domains[$0].uLower < domains[$1].uLower
        }
        var hulls = domains
        func build(_ lower: Int, _ upper: Int, using execution: inout OriginalQueryExecution) throws -> RetainedBounds {
            try execution.consumeWork(1)
            let middle = (lower + upper) / 2
            var hull = domains[order[middle]]
            for range in [lower..<middle, (middle + 1)..<upper] where !range.isEmpty {
                let child = try build(range.lowerBound, range.upperBound, using: &execution)
                hull = RetainedBounds(uLower: min(hull.uLower, child.uLower),
                    uUpper: max(hull.uUpper, child.uUpper), vLower: min(hull.vLower, child.vLower),
                    vUpper: max(hull.vUpper, child.vUpper))
            }
            hulls[middle] = hull
            return hull
        }
        _ = try build(0, order.count, using: &execution)
        func candidates(_ region: RetainedBounds, strict: Bool, using execution: inout OriginalQueryExecution) throws -> [Int] {
            func overlaps(_ bounds: RetainedBounds) -> Bool {
                let du = min(bounds.uUpper, region.uUpper) - max(bounds.uLower, region.uLower)
                let dv = min(bounds.vUpper, region.vUpper) - max(bounds.vLower, region.vLower)
                return strict ? du > 0 && dv > 0 : du >= 0 && dv >= 0
            }
            var result: [Int] = []
            var resultCapacity = 0
            func visit(_ lower: Int, _ upper: Int, using execution: inout OriginalQueryExecution) throws {
                try execution.consumeWork(1)
                guard lower < upper else { return }
                let middle = (lower + upper) / 2
                guard overlaps(hulls[middle]) else { return }
                let index = order[middle]
                if overlaps(domains[index]) {
                    try OriginalCoefficientAllocation.reserveAppend(to: &result, capacity: &resultCapacity, using: &execution)
                    result.append(index)
                }
                try visit(lower, middle, using: &execution)
                try visit(middle + 1, upper, using: &execution)
            }
            try visit(0, order.count, using: &execution)
            try OriginalCoefficientAllocation.reserve(count: result.count, of: Int.self, using: &execution)
            return try result.sorted { try execution.consumeWork(1); return $0 < $1 }
        }
        for firstIndex in 0..<(cells.count - 1) {
            let first = domains[firstIndex]
            for secondIndex in try candidates(first, strict: false, using: &execution) where secondIndex > firstIndex {
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
                    try OriginalCoefficientAllocation.reserve(count: 2, of: Int.self, using: &execution)
                    regionIndexes = [firstIndex, secondIndex]
                } else {
                    regionIndexes = try candidates(region, strict: true, using: &execution)
                }
                try OriginalCoefficientAllocation.reserve(count: regionIndexes.count, of: RationalBezierSurfaceDifferentialBounds.self, using: &execution)
                let regionBounds = regionIndexes.map { cells[$0].differentialBounds }
                if try projectionProvesInjective(bounds: regionBounds, using: &execution) == false {
                    return regionIndexes
                }
                if certifiedRegions.count < maximumPairCellCount {
                    if certifiedRegions.count == certifiedCapacity {
                        let capacity = certifiedCapacity == 0 ? 1 : try exactScalarCount(certifiedCapacity, 2, multiply: true)
                        try OriginalCoefficientAllocation.reserve(count: capacity, of: RetainedBounds.self, using: &execution)
                        certifiedRegions.reserveCapacity(capacity); certifiedCapacity = capacity
                    }
                    certifiedRegions.insert(region)
                }
            }
        }
        return nil
    }

    private func subdivide(
        indexes: [Int],
        cells: inout [Cell],
        tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws {
        let slots = indexes.count.multipliedReportingOverflow(by: 2)
        guard !slots.overflow else { throw GeometryConversionError.resourceLimitExceeded("Native subdivision index storage overflows.") }
        try OriginalCoefficientAllocation.reserve(count: slots.partialValue, of: Int.self, using: &execution)
        var unique = Set<Int>(minimumCapacity: indexes.count)
        for index in indexes { try execution.consumeWork(1); unique.insert(index) }
        let uniqueIndexes = try unique.sorted { try execution.consumeWork(1); return $0 > $1 }
        guard uniqueIndexes.isEmpty == false else {
            throw resourceLimit(
                residual: 0.0,
                tolerance: tolerance,
                message: "B-spline surface embedding found an empty unresolved region."
            )
        }
        for index in uniqueIndexes {
            try execution.consumeWork(1)
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
            try OriginalCoefficientAllocation.reserve(count: 4, of: Cell.self, using: &execution)
            let children = try cell.patch.subdivided(using: &execution).map {
                try Cell(patch: $0, depth: cell.depth + 1, original: cell.original, stationaryDomain: cell.stationaryDomain, using: &execution)
            }
            try OriginalCoefficientAllocation.reserve(count: try exactScalarCount(cells.count, 3, multiply: false), of: Cell.self, using: &execution)
            cells.reserveCapacity(cells.count + 3)
            cells.remove(at: index)
            cells.insert(contentsOf: children, at: index)
        }
    }

    private func projectionProvesInjective(
        bounds: [RationalBezierSurfaceDifferentialBounds],
    using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        guard bounds.isEmpty == false else { return false }
        for axes in try projectionCandidates(from: bounds, using: &execution) {
            var firstSign: Int?
            var secondSign: Int?
            var determinantSign: Int?
            var isConsistent = true
            for bound in bounds {
                try execution.consumeWork(1)
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
        from bounds: [RationalBezierSurfaceDifferentialBounds],
    using execution: inout OriginalQueryExecution) throws -> [ProjectionAxes] {
        let slots = bounds.count.addingReportingOverflow(7)
        guard !slots.overflow else { throw GeometryConversionError.resourceLimitExceeded("Native projection candidate storage overflows.") }
        try OriginalCoefficientAllocation.reserve(count: slots.partialValue, of: ProjectionAxes.self, using: &execution)
        var candidates: [ProjectionAxes] = []; candidates.reserveCapacity(slots.partialValue)
        candidates.append(ProjectionAxes(first: .unitX, second: .unitY))
        candidates.append(ProjectionAxes(first: .unitY, second: .unitX))
        candidates.append(ProjectionAxes(first: .unitX, second: .unitZ))
        candidates.append(ProjectionAxes(first: .unitZ, second: .unitX))
        candidates.append(ProjectionAxes(first: .unitY, second: .unitZ))
        candidates.append(ProjectionAxes(first: .unitZ, second: .unitY))
        var accumulatedU = Vector3D.zero
        var accumulatedV = Vector3D.zero
        for bound in bounds {
            try execution.consumeWork(1)
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
        allowedCornerContacts: [(first: Point2D, second: Point2D)] = [],
    using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        try tolerance.validate()
        try first.validate(tolerance: tolerance, using: &execution)
        try second.validate(tolerance: tolerance, using: &execution)
        guard allowedCornerContacts.count <= 4,
              Set(allowedCornerContacts.map({ $0.first })).count == allowedCornerContacts.count,
              Set(allowedCornerContacts.map({ $0.second })).count == allowedCornerContacts.count else {
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
        let firstPatches = try BSplineSurfaceBezierDecomposer().surfacePatches(surface: first, tolerance: tolerance, using: &execution)
        let secondPatches = try BSplineSurfaceBezierDecomposer().surfacePatches(surface: second, tolerance: tolerance, using: &execution)
        guard !firstPatches.isEmpty, !secondPatches.isEmpty,
              firstPatches.count <= maximumCellCount, secondPatches.count <= maximumCellCount else {
            throw resourceLimit(residual: Double(max(firstPatches.count, secondPatches.count)), tolerance: tolerance,
                message: "Surface separation requires nonempty patch sets within the cell budget.")
        }
        func originals(_ source: BSplineSurface3D, _ patches: [RationalBezierSurfacePatch3D], using execution: inout OriginalQueryExecution) throws -> [NativeSurfaceOriginalCellChart] {
            guard case let .closed(u0, u1) = source.uDomain, case let .closed(v0, v1) = source.vDomain else {
                throw GeometryConversionError.invalidInput("Original chart separation requires finite native domains.")
            }
            let atlas = try NativeSurfaceOriginalAtlas(source: source, over: SurfaceParameterBox(
                    u: ScalarInterval(lower: u0, upper: u1), v: ScalarInterval(lower: v0, upper: v1)),
                maximumSpanCount: maximumCellCount, tolerance: tolerance, using: &execution)
            try OriginalCoefficientAllocation.reserve(count: patches.count, of: NativeSurfaceOriginalCellChart.self, using: &execution)
            return try patches.map { patch in
                let box = try Self.parameterBox(of: patch)
                return .init(law: try atlas.selected(over: box, using: &execution), nativeDomain: box, workingDomain: box)
            }
        }
        let firstOriginals = try originals(first, firstPatches, using: &execution), secondOriginals = try originals(second, secondPatches, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: NativeSurfaceEmbeddingPreparationReservation.sum([firstPatches.count, secondPatches.count]),
            of: BoundingBox3D.self, using: &execution)
        let firstBounds = try firstPatches.indices.map { try firstOriginals[$0].positionBounds(
            over: Self.parameterBox(of: firstPatches[$0]), using: &execution) }
        let secondBounds = try secondPatches.indices.map { try secondOriginals[$0].positionBounds(
            over: Self.parameterBox(of: secondPatches[$0]), using: &execution) }
        var visited = 0
        for i in firstPatches.indices {
            for j in secondPatches.indices {
                try consumeSeparationCell(&visited, tolerance: tolerance, using: &execution)
                guard firstBounds[i].intersects(secondBounds[j], tolerance: tolerance.distance) else { continue }
                try certifyPairSeparation(first: firstPatches[i], second: secondPatches[j],
                    firstOriginal: firstOriginals[i], secondOriginal: secondOriginals[j],
                    visited: &visited, tolerance: tolerance, allowedCornerContacts: allowedCornerContacts, using: &execution)
            }
        }
            try execution.checkpoint()
    }

    /// Certifies cross-surface separation except at two paired opposite boundaries.
    public func validateOppositeBoundaryContacts(
        first: BSplineSurface3D, firstBoundaries: [SurfaceParameterBoundary],
        second: BSplineSurface3D, secondBoundaries: [SurfaceParameterBoundary],
        tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        try tolerance.validate()
        try first.validate(tolerance: tolerance, using: &execution)
        try second.validate(tolerance: tolerance, using: &execution)
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
        func halves(_ surface: BSplineSurface3D, _ sides: [SurfaceParameterBoundary], using execution: inout OriginalQueryExecution) throws -> [SurfaceParameterBox] {
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
            try OriginalCoefficientAllocation.reserve(count: sides.count, of: SurfaceParameterBox.self, using: &execution)
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
        let a = try halves(first, firstBoundaries, using: &execution), b = try halves(second, secondBoundaries, using: &execution)
        let proof = Self(maximumLocalSubdivisionDepth: maximumLocalSubdivisionDepth,
            maximumCellCount: maximumCellCount / 4, maximumPairSubdivisionDepth: maximumPairSubdivisionDepth,
            maximumPairCellCount: maximumPairCellCount / 4)
        try execution.withGeometricDepthOffset(1) { execution in
        for i in a.indices {
            for j in b.indices {
                if i == j {
                    try proof.validateAdjacentRegions(first: first, firstBoundary: firstBoundaries[i], firstRegion: a[i],
                        second: second, secondBoundary: secondBoundaries[j], secondRegion: b[j], tolerance: tolerance, using: &execution)
                } else {
                    try proof.validateOriginalRegionSeparation(first: first, firstRegion: a[i],
                        second: second, secondRegion: b[j], tolerance: tolerance, using: &execution)
                }
            }
        }
        }
            try execution.checkpoint()
    }

    private func validateOriginalRegionSeparation(first: BSplineSurface3D, firstRegion: SurfaceParameterBox,
        second: BSplineSurface3D, secondRegion: SurfaceParameterBox, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        func cells(_ source: BSplineSurface3D, _ region: SurfaceParameterBox, using execution: inout OriginalQueryExecution) throws
            -> [(RationalBezierSurfacePatch3D, NativeSurfaceOriginalCellChart, BoundingBox3D)] {
            let atlas = try NativeSurfaceOriginalAtlas(source: source, over: region,
                maximumSpanCount: maximumCellCount, tolerance: tolerance, using: &execution)
            let patches = try clippedPatches(surface: source, bounds: RetainedBounds(
                uLower: region.u.lower, uUpper: region.u.upper, vLower: region.v.lower,
                vUpper: region.v.upper), tolerance: tolerance, using: &execution)
            guard !patches.isEmpty, patches.count <= maximumCellCount else {
                throw resourceLimit(residual: Double(patches.count), tolerance: tolerance,
                    message: "Original regional separation exhausted its native cell capacity.")
            }
            try OriginalCoefficientAllocation.reserve(count: patches.count,
                of: (RationalBezierSurfacePatch3D, NativeSurfaceOriginalCellChart, BoundingBox3D).self, using: &execution)
            return try patches.map { patch in
                let box = try Self.parameterBox(of: patch)
                let original = NativeSurfaceOriginalCellChart(law: try atlas.selected(over: box, using: &execution),
                    nativeDomain: box, workingDomain: box)
                return (patch, original, try original.positionBounds(over: box, using: &execution))
            }
        }
        let a = try cells(first, firstRegion, using: &execution), b = try cells(second, secondRegion, using: &execution)
        var visited = 0
        for first in a { for second in b {
            try consumeSeparationCell(&visited, tolerance: tolerance, using: &execution)
            if !first.2.intersects(second.2, tolerance: tolerance.distance) { continue }
            try certifyPairSeparation(first: first.0, second: second.0,
                firstOriginal: first.1, secondOriginal: second.1,
                visited: &visited, tolerance: tolerance, allowedCornerContacts: [], using: &execution)
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
        tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        try validateAdjacentRegions(first: first, firstBoundary: firstBoundary, firstRegion: nil,
            second: second, secondBoundary: secondBoundary, secondRegion: nil, tolerance: tolerance, using: &execution)
            try execution.checkpoint()
    }

    private func validateAdjacentRegions(first: BSplineSurface3D,
        firstBoundary: SurfaceParameterBoundary, firstRegion: SurfaceParameterBox?,
        second: BSplineSurface3D, secondBoundary: SurfaceParameterBoundary,
        secondRegion: SurfaceParameterBox?, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try tolerance.validate()
        try first.validate(tolerance: tolerance, using: &execution)
        try second.validate(tolerance: tolerance, using: &execution)
        guard maximumCellCount > 0, maximumLocalSubdivisionDepth >= 0,
              maximumPairSubdivisionDepth >= 0, maximumPairCellCount > 0 else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Adjacent surface admission requires a positive cell budget.")
        }
        let policy = execution.effectiveAllocationPolicy
        let phaseOne = try execution.withAllocationScope(policy: policy, maxCombinedUnits: maximumPairCellCount) { execution in
            try execution.withProofScope(maximum: ExactScalarDepth(value: maximumPairSubdivisionDepth, coefficient: maximumPairSubdivisionDepth)) { execution in
        let issuer = OriginalSurfaceBoundarySourceIssuer()
        let originalFirstSeam = try issuer.boundary(of: .bSpline(first), at: firstBoundary,
            maximumDepth: maximumPairSubdivisionDepth, maximumSpanCount: maximumCellCount, tolerance: tolerance, using: &execution)
        let originalSecondSeam = try issuer.boundary(of: .bSpline(second), at: secondBoundary,
            maximumDepth: maximumPairSubdivisionDepth, maximumSpanCount: maximumCellCount, tolerance: tolerance, using: &execution)
        let reverseSecond: Bool
        if try OriginalSplineTraversalIdentity().proves(originalFirstSeam, originalSecondSeam,
            usage: &execution) { reverseSecond = false }
        else if try OriginalSplineTraversalIdentity().proves(originalFirstSeam,
            originalSecondSeam.reversed(), usage: &execution) { reverseSecond = true }
        else {
            throw resourceLimit(residual: 0, tolerance: tolerance,
                message: "Adjacent original spline boundaries do not share the same directed whole seam law.")
        }
                guard let consumed = execution.allocationScopeCombinedUnits else { throw ExactScalarFailure.invalidEvidence }
                return (reverseSecond, consumed)
            }
        }
        let reverseSecond = phaseOne.0
        let afterSeam = maximumPairCellCount - phaseOne.1
        try OriginalSplineSurfaceContinuityAdmission().validate(first, tolerance: tolerance, usage: &execution)
        try OriginalSplineSurfaceContinuityAdmission().validate(second, tolerance: tolerance, usage: &execution)
        if try originalAdjacentProjection(first: first, firstBoundary: firstBoundary,
            second: second, secondBoundary: secondBoundary, reverseSecond: reverseSecond,
            firstRegion: firstRegion, secondRegion: secondRegion, tolerance: tolerance, using: &execution) { try execution.checkpoint(); return }
        func chart(_ source: BSplineSurface3D, boundary: SurfaceParameterBoundary,
                   atUpper: Bool, using execution: inout OriginalQueryExecution) throws -> BSplineSurface3D {
            try execution.consumeWork(1)
            let count = try NativeSurfaceEmbeddingPreparationReservation.product([source.uControlPointCount, source.vControlPointCount])
            try OriginalCoefficientAllocation.reserve(count: NativeSurfaceEmbeddingPreparationReservation.sum([
                NativeSurfaceEmbeddingPreparationReservation.product([count, 12]),
                NativeSurfaceEmbeddingPreparationReservation.product([
                    NativeSurfaceEmbeddingPreparationReservation.sum([source.uControlPointCount, source.vControlPointCount]), 9]),
                source.uKnots.count, source.vKnots.count]), of: Double.self, using: &execution)
            try execution.consumeWork(NativeSurfaceEmbeddingPreparationReservation.product([count, 6]))
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
        let a = try chart(first, boundary: firstBoundary, atUpper: true, using: &execution)
        var b = try chart(second, boundary: secondBoundary, atUpper: false, using: &execution)
        if reverseSecond {
            let sum = b.uKnots[0] + b.uKnots[b.uKnots.count - 1]
            try OriginalCoefficientAllocation.reserve(count: b.uKnots.count, of: Double.self, using: &execution)
            try execution.consumeWork(b.uKnots.count)
            let count = try NativeSurfaceEmbeddingPreparationReservation.product([b.uControlPointCount, b.vControlPointCount, 2])
            try OriginalCoefficientAllocation.reserve(count: count, of: Double.self, using: &execution); try execution.consumeWork(count)
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
        if clamped(a), clamped(b), try straightSeamSeparates(a, b, using: &execution) {
            guard maximumCellCount >= 2, maximumPairCellCount >= 2 else {
                throw resourceLimit(residual: 2, tolerance: tolerance,
                    message: "Adjacent charts require local and pair budgets for both surfaces.")
            }
            let local = Self(maximumLocalSubdivisionDepth: maximumLocalSubdivisionDepth,
                maximumCellCount: maximumCellCount / 2,
                maximumPairSubdivisionDepth: maximumPairSubdivisionDepth,
                maximumPairCellCount: maximumPairCellCount / 2)
            for index in 0..<2 {
                let surface = index == 0 ? first : second
                let region = index == 0 ? firstRegion : secondRegion
                try local.validate(surface, uDomain: region.map { .closed($0.u.lower, $0.u.upper) } ?? surface.uDomain,
                    vDomain: region.map { .closed($0.v.lower, $0.v.upper) } ?? surface.vDomain,
                    tolerance: tolerance, allowStationaryBoundaryParameterization: true, using: &execution)
            }
            try execution.checkpoint(); return
        }
        guard clamped(a), clamped(b) else {
            throw resourceLimit(residual: 0, tolerance: tolerance,
                message: "Adjacent spline charts require clamped nominated boundaries.")
        }
        // Working free stations must retain the exact original traversal. Rounded
        // candidate transverse labels only schedule a continuous per-owner chart.
        let phaseTwo = try execution.withAllocationScope(policy: policy, maxCombinedUnits: afterSeam) { execution in
            try execution.withProofScope(maximum: ExactScalarDepth(value: maximumPairSubdivisionDepth, coefficient: maximumPairSubdivisionDepth)) { execution in
                guard a.uDomain == b.uDomain,
              try exactFreeScheduling(source: first, boundary: firstBoundary, candidate: a,
                reversed: false, usage: &execution),
              try exactFreeScheduling(source: second, boundary: secondBoundary, candidate: b,
                reversed: reverseSecond, usage: &execution) else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): The original global projection
            // route above covers normalized unequal free domains. Loft's local
            // touching-cell continuation still needs exact nonrepresentable
            // shared seam cuts before it can publish those other original charts.
            throw resourceLimit(residual: 0, tolerance: tolerance,
                message: "Adjacent local subdivision requires exact original free-axis scheduling stations.")
        }
                guard let consumed = execution.allocationScopeCombinedUnits else { throw ExactScalarFailure.invalidEvidence }
                return consumed
            }
        }
        let remaining = afterSeam - phaseTwo
        guard remaining > 0 else {
            throw resourceLimit(residual: Double(maximumPairCellCount), tolerance: tolerance,
                message: "Original seam algebra exhausted the adjacent pair allowance.")
        }
        let continuation = Self(maximumLocalSubdivisionDepth: maximumLocalSubdivisionDepth,
            maximumCellCount: maximumCellCount, maximumPairSubdivisionDepth: maximumPairSubdivisionDepth,
            maximumPairCellCount: remaining)
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
                maximumSpanCount: maximumCellCount, tolerance: tolerance, using: &execution)
            let patches = try clippedPatches(surface: raw,
                bounds: RetainedBounds(uLower: whole.u.lower, uUpper: whole.u.upper,
                    vLower: whole.v.lower, vUpper: whole.v.upper), tolerance: tolerance, using: &execution)
            guard !patches.isEmpty, patches.count <= maximumCellCount - cells.count else {
                throw resourceLimit(residual: Double(patches.count), tolerance: tolerance,
                    message: "Adjacent original charts exhausted the cell capacity.")
            }
            let transverse = swapsAxes ? whole.u : whole.v
            let knots = swapsAxes ? raw.uKnots : raw.vKnots
            try OriginalCoefficientAllocation.reserve(count: NativeSurfaceEmbeddingPreparationReservation.sum([knots.count, 2]), of: Double.self, using: &execution)
            var cuts = [transverse.lower]
            for knot in knots {
                try execution.consumeWork(1)
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
            let capacity = try exactScalarCount(cells.count, patches.count, multiply: false)
            try OriginalCoefficientAllocation.reserve(count: capacity, of: Cell.self, using: &execution)
            cells.reserveCapacity(capacity)
            for patch in patches {
                let nativeBox = try Self.parameterBox(of: patch)
                let law = try atlas.selected(over: nativeBox, using: &execution)
                let nativeTransverse = swapsAxes ? nativeBox.u : nativeBox.v
                var ordinal: Int?
                for i in 0..<intervalCount {
                    try execution.consumeWork(1)
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
                try OriginalCoefficientAllocation.reserve(count: NativeSurfaceEmbeddingPreparationReservation.sum([
                    NativeSurfaceEmbeddingPreparationReservation.product([netCount, 12]),
                    NativeSurfaceEmbeddingPreparationReservation.product([
                        NativeSurfaceEmbeddingPreparationReservation.sum([patch.controlPoints.count, patch.controlPoints[0].count]), 9])]), of: Double.self, using: &execution)
                try execution.consumeWork(NativeSurfaceEmbeddingPreparationReservation.product([netCount, 6]))
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
                    stationaryDomain: stationaryDomain, using: &execution))
            }
            for law in atlas.laws {
                try execution.consumeWork(1)
                let loU = max(law.native.uBounds.lower, whole.u.lower), hiU = min(law.native.uBounds.upper, whole.u.upper)
                let loV = max(law.native.vBounds.lower, whole.v.lower), hiV = min(law.native.vBounds.upper, whole.v.upper)
                if loU >= hiU || loV >= hiV { continue }
                var covered = false
                for cellIndex in originalCellStart..<cells.count {
                    try execution.consumeWork(1)
                    let owner = cells[cellIndex].original.law.native
                    if owner.uSpanIndex == law.native.uSpanIndex, owner.vSpanIndex == law.native.vSpanIndex,
                       owner.uCycle == law.native.uCycle, owner.vCycle == law.native.vCycle { covered = true; break }
                }
                guard covered else {
                    throw GeometryConversionError.invalidInput("Adjacent decomposition omitted a positive original native owner.")
                }
            }
        }
        if try projectionProvesInjective(bounds: OriginalCoefficientAllocation.map(elements: cells, using: &execution) { cell, _ in cell.differentialBounds }, using: &execution) { try execution.checkpoint(); return }
        try OriginalCoefficientAllocation.reserve(count: cells.count, of: NativeSurfaceOriginalCellChart.self, using: &execution)
        let originalCharts = cells.map({ $0.original })
        func sourceStation(_ u: Double, _ v: Double, using execution: inout OriginalQueryExecution) throws -> (BSplineSurface3D, Double, Double) {
            let query = try SurfaceParameterBox(u: ScalarInterval(lower: u, upper: u),
                v: ScalarInterval(lower: v, upper: v))
            for original in originalCharts {
                try execution.consumeWork(1)
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
        func point(_ u: Double, _ v: Double, _ execution: inout OriginalQueryExecution) throws -> Point3D {
            let (surface, nativeU, nativeV) = try sourceStation(u, v, using: &execution)

            return try surface.point(u: nativeU, v: nativeV, tolerance: tolerance, using: &execution)
        }
        var comparisons = 0
        for i in cells.indices {
            for j in cells.indices where j > i {
                try continuation.consumeSeparationCell(&comparisons, tolerance: tolerance, using: &execution)
                try rejectSampledCoincidence(first: cells[i].patch, second: cells[j].patch,
                    point: point, tolerance: tolerance, using: &execution)
            }
        }
        try continuation.certifyLocalInjectivity(cells: &cells, normalAt: { u, v, execution in
            let (surface, nativeU, nativeV) = try sourceStation(u, v, using: &execution)

            return try surface.normal(u: nativeU, v: nativeV, tolerance: tolerance, using: &execution)
        }, tolerance: tolerance, using: &execution)
        guard comparisons < remaining else {
            throw resourceLimit(residual: Double(comparisons), tolerance: tolerance,
                message: "Adjacent chart comparisons exhausted the remaining original proof allowance.")
        }
        let separation = Self(maximumLocalSubdivisionDepth: maximumLocalSubdivisionDepth,
            maximumCellCount: maximumCellCount, maximumPairSubdivisionDepth: maximumPairSubdivisionDepth,
            maximumPairCellCount: remaining - comparisons)
        try separation.certifySeparatedCells(cells, point: point, tolerance: tolerance, using: &execution)
    }

    private func exactFreeScheduling(source: BSplineSurface3D, boundary: SurfaceParameterBoundary,
        candidate: BSplineSurface3D, reversed: Bool, usage: inout OriginalQueryExecution) throws -> Bool {
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Bool {
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
                maximumSpanCount: maximumCellCount, tolerance: tolerance, using: &execution)
            guard atlas.laws.count <= maximumCellCount - fields.count else {
                throw resourceLimit(residual: Double(atlas.laws.count), tolerance: tolerance,
                    message: "Original adjacent projection exhausted its cumulative native owner capacity.")
            }
            let fieldCapacity = try exactScalarCount(fields.count, atlas.laws.count, multiply: false)
            try OriginalCoefficientAllocation.reserve(count: fieldCapacity, of: RationalBezierSurfaceDifferentialBounds.self, using: &execution)
            fields.reserveCapacity(fieldCapacity)
            for law in atlas.laws {
                try execution.visitGeometricCell(depth: 0)
                let loU = max(law.native.uBounds.lower, whole.u.lower)
                let hiU = min(law.native.uBounds.upper, whole.u.upper)
                let loV = max(law.native.vBounds.lower, whole.v.lower)
                let hiV = min(law.native.vBounds.upper, whole.v.upper)
                guard loU < hiU, loV < hiV else { continue }
                let box = try SurfaceParameterBox(u: ScalarInterval(lower: loU, upper: hiU),
                    v: ScalarInterval(lower: loV, upper: hiV))
                var stationary: Set<SurfaceParameterBoundary> = []
                try OriginalCoefficientAllocation.reserve(count: 4, of: SurfaceParameterBoundary.self, using: &execution)
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
                fields.append(try chart.fields(overNative: box, nativeStationary: stationary, using: &execution).0)
            }
        }
        return try projectionProvesInjective(bounds: fields, using: &execution)
    }

    private func straightSeamSeparates(_ a: BSplineSurface3D, _ b: BSplineSurface3D, using execution: inout OriginalQueryExecution) throws -> Bool {
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
            func isStraight(_ points: [Point3D], using execution: inout OriginalQueryExecution) throws -> Bool {
                let increasing = coordinate(points[0], axis) < coordinate(points[points.count - 1], axis)
                for i in points.indices {
                    for other in [c1, c2] {
                        func projected(_ p: Point3D) -> Point2D {
                            Point2D(x: coordinate(p, axis), y: coordinate(p, other))
                        }
                        guard try RobustPredicates.orientation2D(projected(start), projected(end),
                            relativeTo: projected(points[i]), determinantTolerance: 0, using: &execution) == .zero else { return false }
                    }
                    if i > 0 {
                        let previous = coordinate(points[i - 1], axis), value = coordinate(points[i], axis)
                        if increasing ? value < previous : value > previous { return false }
                    }
                }
                return true
            }
            guard try isStraight(first, using: &execution), try isStraight(second, using: &execution) else { continue }
            // This third point only proposes a plane through the exact seam.
            // Every off-seam control must pass a strict orientation proof.
            let pa = a.controlPoints[0][a.controlPoints[0].count / 2]
            let pb = b.controlPoints[b.controlPoints.count - 1][b.controlPoints[0].count / 2]
            let third = start + (end - start).cross(pa - pb)
            guard third.x.isFinite, third.y.isFinite, third.z.isFinite else { return false }
            func sign(_ p: Point3D, using execution: inout OriginalQueryExecution) throws -> RobustSign {
                try RobustPredicates.orientation3D(start, end, third,
                    relativeTo: p, determinantTolerance: 0, using: &execution)
            }
            let firstSign = try sign(pa, using: &execution), secondSign = try sign(pb, using: &execution)
            let side = firstSign == .zero
                ? (secondSign == .positive ? RobustSign.negative : RobustSign.positive) : firstSign
            guard side == .positive || side == .negative else { return false }
            let opposite: RobustSign = side == .positive ? .negative : .positive
            var firstStrict = true, secondStrict = true
            let firstSeparated = try a.controlPoints.dropLast().allSatisfy { row in
                try row.allSatisfy {
                    let value = try sign($0, using: &execution)
                    if value == .zero { firstStrict = false }
                    return value == side || value == .zero
                }
            }
            let secondSeparated = try b.controlPoints.dropFirst().allSatisfy { row in
                try row.allSatisfy {
                    let value = try sign($0, using: &execution)
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

    private func consumeSeparationCell(_ visited: inout Int, tolerance: ModelingTolerance, depth: Int = 0, using execution: inout OriginalQueryExecution) throws {
        guard visited < maximumPairCellCount else {
            throw resourceLimit(residual: Double(visited), tolerance: tolerance,
                message: "B-spline surface separation exhausted its pair cell budget.")
        }
        try execution.visitGeometricCell(depth: depth)
        visited += 1
    }

    private func certifyPairSeparation(
        first: RationalBezierSurfacePatch3D, second: RationalBezierSurfacePatch3D,
        firstOriginal: NativeSurfaceOriginalCellChart, secondOriginal: NativeSurfaceOriginalCellChart,
        visited: inout Int, tolerance: ModelingTolerance,
        allowedCornerContacts: [(first: Point2D, second: Point2D)] = [],
        initialDepth: Int = 0,
    using execution: inout OriginalQueryExecution) throws {
        try execution.withGeometricDepthOffset(initialDepth) { execution in
        try OriginalCoefficientAllocation.reserve(count: 1, of: PairCell.self, using: &execution)
        let firstNet = try NativeSurfaceOriginalCoefficientNet(chart: firstOriginal,
            over: Self.parameterBox(of: first), using: &execution)
        let secondNet = try NativeSurfaceOriginalCoefficientNet(chart: secondOriginal,
            over: Self.parameterBox(of: second), using: &execution)
        var pending = [PairCell(difference: try RationalBezierSurfaceSurfaceDifferencePatch(
            originalFirst: firstNet, originalSecond: secondNet, tolerance: tolerance, using: &execution), depth: 0)]
        var pendingCapacity = 1
        while let pair = pending.popLast() {
            if pair.depth > 0 { try consumeSeparationCell(&visited, tolerance: tolerance, depth: pair.depth, using: &execution) }
            if try pair.difference.excludesZero(using: &execution) { continue }
            if try pair.difference.excludesZeroAlongSurfaceDirections(allowedCornerContacts: allowedCornerContacts, using: &execution) { continue }
            guard pair.depth < maximumPairSubdivisionDepth else {
                throw resourceLimit(residual: Double(pair.depth), tolerance: tolerance,
                    message: "B-spline surface separation could not exclude intersection within the subdivision limit.")
            }
            let parameterIndex = widestParameterIndex(pair.difference)
            let children = try pair.difference.subdivided(parameterIndex: parameterIndex, using: &execution)
            for child in children {
                try OriginalCoefficientAllocation.reserveAppend(to: &pending, capacity: &pendingCapacity, using: &execution)
                pending.append(PairCell(difference: child, depth: pair.depth + 1))
            }
        }
        }
    }

    private func certifySeparatedCells(
        _ cells: [Cell],
        point: (Double, Double, inout OriginalQueryExecution) throws -> Point3D,
        tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws {
        guard cells.count > 1 else { return }
        if try projectionProvesInjective(bounds: OriginalCoefficientAllocation.map(elements: cells, using: &execution) { cell, _ in cell.differentialBounds }, using: &execution) { try execution.checkpoint(); return }
        try OriginalCoefficientAllocation.reserve(count: 3, of: ((Point3D) -> Double).self, using: &execution)
        let axes: [(Point3D) -> Double] = [{ $0.x }, { $0.y }, { $0.z }]
        var axis = axes[0]
        var bestScore = Double.infinity
        for candidate in axes {
            var lower = Double.infinity, upper = -Double.infinity, width = 0.0
            for cell in cells {
                try execution.consumeWork(1)
                let minimum = candidate(cell.bounds.minimum)
                let maximum = candidate(cell.bounds.maximum)
                lower = min(lower, minimum)
                upper = max(upper, maximum)
                width += maximum - minimum
            }
            let score = upper > lower ? width / (upper - lower) : .infinity
            if score < bestScore { axis = candidate; bestScore = score }
        }
        try OriginalCoefficientAllocation.reserve(count: cells.count, of: Double.self, using: &execution)
        let ordered = try cells.indices.sorted {
            try execution.consumeWork(1)
            let a = axis(cells[$0].bounds.minimum), b = axis(cells[$1].bounds.minimum)
            return a == b ? $0 < $1 : a < b
        }
        var visitedPairCells = 0
        for firstOffset in 0..<(ordered.count - 1) {
            let firstIndex = ordered[firstOffset]
            for secondOffset in (firstOffset + 1)..<ordered.count {
                let secondIndex = ordered[secondOffset]
                guard axis(cells[secondIndex].bounds.minimum)
                        <= axis(cells[firstIndex].bounds.maximum) + tolerance.distance else { break }
                try consumeSeparationCell(&visitedPairCells, tolerance: tolerance, depth: max(cells[firstIndex].depth, cells[secondIndex].depth), using: &execution)
                let first = cells[firstIndex].patch
                let second = cells[secondIndex].patch
                guard touches(first, second) == false else { continue }
                guard cells[firstIndex].bounds.intersects(cells[secondIndex].bounds,
                    tolerance: tolerance.distance) else { continue }
                try rejectSampledCoincidence(
                    first: first,
                    second: second,
                    point: point,
                    tolerance: tolerance,
                using: &execution)
                try certifyPairSeparation(first: first, second: second,
                    firstOriginal: cells[firstIndex].original, secondOriginal: cells[secondIndex].original,
                    visited: &visitedPairCells, tolerance: tolerance,
                    initialDepth: max(cells[firstIndex].depth, cells[secondIndex].depth), using: &execution)
            }
        }
    }

    private func rejectSampledCoincidence(
        first: RationalBezierSurfacePatch3D,
        second: RationalBezierSurfacePatch3D,
        point: (Double, Double, inout OriginalQueryExecution) throws -> Point3D,
        tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws {
        let fractions = [0.0, 0.5, 1.0]
        for firstU in fractions {
            for firstV in fractions {
                try execution.consumeWork(1)
                let firstParameter = parameter(
                    in: first,
                    uFraction: firstU,
                    vFraction: firstV
                )
                let firstPoint = try point(firstParameter.x, firstParameter.y, &execution)
                for secondU in fractions {
                    for secondV in fractions {
                        try execution.consumeWork(1)
                        let secondParameter = parameter(
                            in: second,
                            uFraction: secondU,
                            vFraction: secondV
                        )
                        if firstParameter == secondParameter { continue }
                        let secondPoint = try point(secondParameter.x, secondParameter.y, &execution)
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
