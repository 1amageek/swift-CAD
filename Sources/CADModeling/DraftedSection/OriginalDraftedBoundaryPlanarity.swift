import CADCore
import CADGeometry

/// Whole original section-plane admission, independent of construction coefficients.
package struct OriginalDraftedBoundaryPlanarity {
    private struct Cell { let range: ScalarInterval; let depth: Int }

    package func validate(_ generator: OriginalCurveRootSpan3D, on plane: Plane3D,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        let raw = plane.normal
        let scale = max(abs(raw.x), max(abs(raw.y), abs(raw.z)))
        guard plane.origin.isFinite, scale.isFinite, scale > 0 else {
            throw GeometryConversionError.invalidInput("Original section planarity requires a finite plane with a nonzero raw normal.")
        }
        let equation = try OriginalSupportingPlaneEquation.prepared(source: .plane(plane),
            tolerance: tolerance, remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth, usage: &execution)
        if try OriginalSplineTraversalPolynomialPiece.supports(generator, usage: &execution) {
            let pieces = try OriginalSplineTraversalPolynomialPiece.pieces(generator, usage: &execution)
            var exact = !pieces.isEmpty
            for piece in pieces {
                if try !equation.polynomial(piece.homogeneous, includeOffset: true, usage: &execution).isZero { exact = false }
            }
            if exact {
                try CurrentTaskCancellationChecker().checkCancellation()
                return
            }
        }
        let direction: IntervalVector3DBounds
        if plane.uDirection != nil {
            direction = try .init(x: equation.normal.x.outwardInterval(usage: &execution),
                y: equation.normal.y.outwardInterval(usage: &execution),
                z: equation.normal.z.outwardInterval(usage: &execution))
        } else {
            direction = .init(x: .exact(raw.x), y: .exact(raw.y), z: .exact(raw.z))
        }
        guard let normal = try direction.normalized(using: &execution) else {
            throw GeometryConversionError.resourceLimitExceeded("Original section normal has no finite outward normalization.")
        }
        let maximumDepth = min(32, execution.effectiveLimits.maximumSubdivisionDepth)
        try execution.retainStorage(bytes: (maximumDepth + 1) * MemoryLayout<Cell>.stride)
        var pending: [Cell] = []; pending.reserveCapacity(maximumDepth + 1)
        pending.append(.init(range: try .init(lower: 0, upper: 1), depth: 0))
        var remaining = 65_536
        while let cell = pending.popLast() {
            guard remaining > 0 else {
                throw GeometryConversionError.resourceLimitExceeded("Original section planarity exhausted its retained cell allowance.")
            }
            remaining -= 1
            try execution.visitGeometricCell(depth: cell.depth)
            let q = try generator.intervalTaylorJet(over: cell.range, throughOrder: 0,
                tolerance: tolerance,
                maximumSpanCount: min(4096, execution.effectiveLimits.maximumSpans),
                maximumSubdivisionDepth: maximumDepth - cell.depth,
                remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth, using: &execution)
            let distance = try (q.x.coefficient(0, 0) - .exact(plane.origin.x)) * normal.x
                + (q.y.coefficient(0, 0) - .exact(plane.origin.y)) * normal.y
                + (q.z.coefficient(0, 0) - .exact(plane.origin.z)) * normal.z
            if distance.lower >= -tolerance.distance, distance.upper <= tolerance.distance { continue }
            if distance.lower > tolerance.distance || distance.upper < -tolerance.distance {
                throw GeometryConversionError.invalidInput("An original extrusion boundary leaves its declared section plane.")
            }
            let middle = cell.range.lower + cell.range.width * 0.5
            guard cell.depth < maximumDepth, middle > cell.range.lower, middle < cell.range.upper else {
                throw GeometryConversionError.resourceLimitExceeded("Original section-plane correspondence remains unresolved within its retained depth.")
            }
            pending.append(.init(range: try .init(lower: middle, upper: cell.range.upper), depth: cell.depth + 1))
            pending.append(.init(range: try .init(lower: cell.range.lower, upper: middle), depth: cell.depth + 1))
        }
        try CurrentTaskCancellationChecker().checkCancellation()
    }
}
