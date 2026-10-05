import CADCore
import CADGeometry

/// Whole original line integral; display points cannot select loop direction.
package struct OriginalPlanarLoopOrientation: Sendable {
    private struct Boundary {
        let source: OriginalCurveSpanSource
        let startParameter: Double
        let endParameter: Double
    }
    private struct Cell {
        let segment: Int
        let lower: Double
        let upper: Double
        let depth: Int
        let integral: OutwardScalarInterval
    }

    package init() {}

    package func counterclockwise(source: OriginalCurveSpanSource,
        startParameter: Double, endParameter: Double, origin: Point3D, normal: Vector3D,
        tolerance: ModelingTolerance, admission: GeometryConversionAdmission) throws -> Bool {
        guard startParameter.isFinite, endParameter.isFinite, startParameter != endParameter else {
            throw failure("Original closed curve winding requires distinct finite authored endpoints.", tolerance)
        }
        try admission.chargeStorage(bytes: MemoryLayout<Boundary>.stride)
        return try counterclockwise([Boundary(source: source, startParameter: startParameter,
            endParameter: endParameter)], origin: origin, normal: normal,
            tolerance: tolerance, admission: admission)
    }

    package func counterclockwise(_ segments: [OriginalFaceSectionSegment],
        origin: Point3D, normal: Vector3D, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws -> Bool {
        try admission.chargeStorage(bytes: segments.count * MemoryLayout<Boundary>.stride)
        let boundaries = try segments.map { segment in
            try admission.chargeWork()
            return Boundary(source: segment.source, startParameter: segment.startParameter,
                endParameter: segment.endParameter)
        }
        return try counterclockwise(boundaries, origin: origin, normal: normal,
            tolerance: tolerance, admission: admission)
    }

    package func counterclockwise(charts: [OriginalCurveSpanParameterChart],
        origin: Point3D, normal: Vector3D, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws -> Bool {
        try admission.chargeStorage(bytes: charts.count * MemoryLayout<Boundary>.stride)
        let boundaries = try charts.map { chart in
            try admission.chargeWork()
            let curve = try chart.persistentCurve(tolerance: tolerance, admission: admission)
            return Boundary(source: try OriginalCurveSpanSource(curve: curve,
                tolerance: tolerance, admission: admission), startParameter: 0, endParameter: 1)
        }
        return try counterclockwise(boundaries, origin: origin, normal: normal,
            tolerance: tolerance, admission: admission)
    }

    private func counterclockwise(_ segments: [Boundary],
        origin: Point3D, normal: Vector3D, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws -> Bool {
        let limits = GeometryConversionRequirements(maximumPositionError: tolerance.distance,
            maximumTangentAngle: tolerance.angle, maximumCurvatureError: tolerance.distance)
        guard !segments.isEmpty, segments.count <= limits.maximumControlPointCount else {
            throw failure("Original face winding has no admitted complete boundary.", tolerance)
        }
        try admission.chargeStorage(bytes: segments.count * MemoryLayout<PreparedCurveDifferentialEncloser>.stride)
        var sources: [PreparedCurveDifferentialEncloser] = []
        sources.reserveCapacity(segments.count)
        for segment in segments {
            if let prepared = segment.source.prepared, segment.source.preparationTolerance == tolerance {
                sources.append(prepared)
            } else {
                sources.append(try PreparedCurveDifferentialEncloser(curve: segment.source.curve,
                    tolerance: tolerance, remainingSourceDepth: admission.remainingSourceDepth,
                    maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
                    consumeWork: { try admission.chargeWork() },
                    consumeStorage: { try admission.chargeStorage(bytes: $0) },
                    maximumAlgebraicDepth: admission.maximumAlgebraicDepth))
            }
        }
        var cells: [Cell] = []
        var capacity = 0
        var remaining = limits.maximumCertificationBoxes
        func cell(segment index: Int, lower: Double, upper: Double, depth: Int) throws -> Cell {
            guard remaining > 0 else { throw failure("Original face winding exhausted its cell allowance.", tolerance) }
            remaining -= 1
            try admission.visit(depth: depth)
            let receipt = try sources[index].closedNativeJets(
                over: ScalarInterval(lower: lower, upper: upper), tolerance: tolerance,
                maximumSpanCount: limits.maximumControlPointCount,
                maximumSubdivisionDepth: admission.maximumSubdivisionDepth - depth,
                remainingSourceDepth: admission.remainingSourceDepth,
                consumeWork: { try admission.visit(depth: depth) },
                consumeStorage: { try admission.chargeStorage(bytes: $0) })
            var bound: OutwardScalarInterval?
            for owner in receipt.spans {
                try admission.visit(depth: depth)
                let jet = owner.jet
                let x = jet.x.value - .exact(origin.x)
                let y = jet.y.value - .exact(origin.y)
                let z = jet.z.value - .exact(origin.z)
                let cross = (y * jet.z.derivativeU - z * jet.y.derivativeU) * .exact(normal.x)
                    + (z * jet.x.derivativeU - x * jet.z.derivativeU) * .exact(normal.y)
                    + (x * jet.y.derivativeU - y * jet.x.derivativeU) * .exact(normal.z)
                bound = bound.map { .init(lower: min($0.lower, cross.lower), upper: max($0.upper, cross.upper)) } ?? cross
            }
            guard let bound, bound.isFinite else { throw failure("Original face winding lacks a finite owning-jet cover.", tolerance) }
            let direction = segments[index].endParameter > segments[index].startParameter ? 1.0 : -1.0
            let integral = bound * (.exact(upper) - .exact(lower)) * .exact(direction)
            guard integral.isFinite else { throw failure("Original face winding has nonfinite integral bounds.", tolerance) }
            return Cell(segment: index, lower: lower, upper: upper, depth: depth, integral: integral)
        }
        func admitCapacity(_ count: Int) throws {
            guard count <= limits.maximumCertificationBoxes else { throw failure("Original face winding exhausted retained cells.", tolerance) }
            if count > capacity {
                let next = min(limits.maximumCertificationBoxes, max(count, max(8, capacity * 2)))
                try admission.chargeStorage(bytes: next * MemoryLayout<Cell>.stride)
                cells.reserveCapacity(next); capacity = next
            }
        }
        try admitCapacity(segments.count)
        for index in segments.indices {
            cells.append(try cell(segment: index,
                lower: min(segments[index].startParameter, segments[index].endParameter),
                upper: max(segments[index].startParameter, segments[index].endParameter), depth: 0))
        }
        while true {
            var integral = OutwardScalarInterval.exact(0)
            var selected = 0
            var width = -Double.infinity
            for index in cells.indices {
                try admission.visit(depth: cells[index].depth)
                integral = integral + cells[index].integral
                let uncertainty = cells[index].integral.upper - cells[index].integral.lower
                if uncertainty > width { selected = index; width = uncertainty }
            }
            if integral.lower > 0 { return true }
            if integral.upper < 0 { return false }
            let current = cells[selected]
            guard current.depth < admission.maximumSubdivisionDepth else {
                throw failure("Original face winding cannot prove a nonzero oriented area within its depth.", tolerance)
            }
            let middle = current.lower + (current.upper - current.lower) * 0.5
            guard middle > current.lower, middle < current.upper else {
                throw failure("Original face winding subdivision reached native parameter precision.", tolerance)
            }
            let first = try cell(segment: current.segment, lower: current.lower, upper: middle, depth: current.depth + 1)
            let second = try cell(segment: current.segment, lower: middle, upper: current.upper, depth: current.depth + 1)
            try admitCapacity(cells.count + 1)
            cells[selected] = first; cells.append(second)
        }
    }

    private func failure(_ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: .resourceLimitExceeded,
            tolerance: tolerance, message: message)
    }
}
