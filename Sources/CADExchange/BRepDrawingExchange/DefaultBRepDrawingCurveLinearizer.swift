import CADCore
import CADGeometry

public struct DefaultBRepDrawingCurveLinearizer: BRepDrawingCurveLinearizing {
    public init() {}
    public func linearize(_ curve: OrthographicProjectedCurve, from start: Double, to end: Double,
                          maximumDeviation: Double, usage: DrawingExchangeOwner, using execution: inout OriginalQueryExecution) throws -> BRepDrawingCurvePath {
        try linearize(curve, from: start, to: end, maximumDeviation: maximumDeviation, resources: usage.resources, using: &execution)
    }

    func linearize(_ curve: OrthographicProjectedCurve, from start: Double, to end: Double,
                   maximumDeviation: Double, resources: SharedExchangeResourceAccountant, using execution: inout OriginalQueryExecution) throws -> BRepDrawingCurvePath {
        return try execution.withProofScope(maximum: .init(value: resources.limits.maximumAlgebraicDepth, coefficient: resources.limits.maximumAlgebraicDepth)) { execution in
        guard start.isFinite, end.isFinite, start != end, maximumDeviation.isFinite, maximumDeviation > 0 else {
            throw ExportError.invalidMesh("Invalid original drawing interval or deviation allowance.")
        }
        let owner = resources, limits = owner.limits, tolerance = curve.certificationTolerance
        guard execution.budget === resources.originalBudget else {
            throw ExportError.invalidMesh("Drawing curve requires its original invocation execution.")
        }
        let source = try NativeCurveConversionSource(curve.source, tolerance: tolerance, using: &execution)
        func projected(_ box: CoordinateEnclosure3D, position: Bool) throws -> IntervalVector3DBounds {
            var x = OutwardScalarInterval(lower: box.x.lower, upper: box.x.upper)
            var y = OutwardScalarInterval(lower: box.y.lower, upper: box.y.upper)
            var z = OutwardScalarInterval(lower: box.z.lower, upper: box.z.upper)
            if position {
                x = x - .exact(curve.frame.origin.x); y = y - .exact(curve.frame.origin.y)
                z = z - .exact(curve.frame.origin.z)
            }
            func coordinate(_ basis: Vector3D) -> OutwardScalarInterval {
                x * .exact(basis.x) + y * .exact(basis.y) + z * .exact(basis.z)
            }
            let horizontal = coordinate(curve.frame.horizontal), vertical = coordinate(curve.frame.vertical)
            guard horizontal.isFinite, vertical.isFinite else {
                throw ExportError.invalidMesh("Drawing original projected enclosure is nonfinite.")
            }
            return .init(x: horizontal, y: vertical, z: .exact(0))
        }
        func station(_ parameter: Double, using execution: inout OriginalQueryExecution) throws -> (point: Point2D, error: Double) {
            let original = try source.enclosure(over: .init(lower: parameter, upper: parameter),
                tolerance: tolerance, using: &execution)
            let box = try projected(original.position, position: true)
            let point = Point2D(x: box.x.midpoint, y: box.y.midpoint)
            let error = IntervalVector3DBounds(x: box.x - .exact(point.x),
                y: box.y - .exact(point.y), z: .exact(0)).lengthUpperBound
            guard point.x.isFinite, point.y.isFinite, error.isFinite else {
                throw ExportError.invalidMesh("Drawing original station uncertainty is nonfinite.")
            }
            return (point, error)
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): Mapped/non-binary and lifted original joins still require their lower retained owning station cover.
        // Public drawing output consumes the actual cover and propagates that lower failure; it must not accept a whole-range derivative hull instead.
        let cover = try source.owningParameterCover(over: .init(lower: min(start, end), upper: max(start, end)),
            tolerance: tolerance, using: &execution)
        let first = try station(start, using: &execution)
        typealias Pending = (Double, Double, Point2D, Point2D, Double, Double, Int)
        let pendingBytes = cover.count.multipliedReportingOverflow(by: MemoryLayout<Pending>.stride)
        guard !pendingBytes.overflow else { throw ExportError.invalidMesh("Drawing owning cover stack storage overflows.") }
        try owner.recordEntities(cover.count)
        try owner.recordBytes(pendingBytes.partialValue)
        try owner.recordEntities(); try owner.recordBytes(MemoryLayout<BRepDrawingCurvePath.Sample>.stride)
        var samples = [BRepDrawingCurvePath.Sample(parameter: start, point: first.point)]
        var pending: [Pending] = []; pending.reserveCapacity(cover.count)
        for index in cover.indices.reversed() {
            try owner.recordIterations()
            let interval = start < end ? cover[index] : cover[cover.count - 1 - index]
            let a = start < end ? interval.lower : interval.upper
            let b = start < end ? interval.upper : interval.lower
            let pa = try station(a, using: &execution), pb = try station(b, using: &execution)
            pending.append((a, b, pa.point, pb.point, pa.error, pb.error, 0))
        }
        while let (a, b, pa, pb, ea, eb, depth) = pending.popLast() {
            try owner.recordIterations(); try owner.checkTime()
            let span = try ScalarInterval(lower: min(a, b), upper: max(a, b))
            let enclosure = try source.enclosure(over: span, tolerance: tolerance, using: &execution)
            let second = try projected(enclosure.secondDerivative, position: false).lengthUpperBound
            let width = OutwardScalarInterval.exact(span.upper) - .exact(span.lower)
            guard let chordError = (OutwardScalarInterval.exact(second) * width * width).divided(by: .exact(8)) else {
                throw ExportError.invalidMesh("Drawing chord bound is nonfinite.")
            }
            let error = chordError + .exact(max(ea, eb))
            guard second.isFinite, error.isFinite else { throw ExportError.invalidMesh("Drawing chord bound is nonfinite.") }
            if error.upper <= maximumDeviation {
                try owner.recordEntities(); try owner.recordBytes(MemoryLayout<BRepDrawingCurvePath.Sample>.stride)
                samples.append(.init(parameter: b, point: pb))
            } else {
                guard depth < limits.maximumCurveSubdivisionDepth else {
                    throw ExportError.invalidMesh("Drawing curve subdivision exceeds the caller's depth allowance.")
                }
                let midpoint = a * 0.5 + b * 0.5
                guard midpoint.isFinite, midpoint != a, midpoint != b else {
                    throw ExportError.invalidMesh("Drawing parameter resolution is exhausted.")
                }
                let middle = try station(midpoint, using: &execution)
                try owner.recordEntities(2); try owner.recordBytes(2 * MemoryLayout<Pending>.stride)
                pending.append((midpoint, b, middle.point, pb, middle.error, eb, depth + 1))
                pending.append((a, midpoint, pa, middle.point, ea, middle.error, depth + 1))
            }
        }
        return BRepDrawingCurvePath(curve: curve, startParameter: start, endParameter: end, samples: samples)

        }
    }
}
