import CADCore
import CADGeometry

public struct DefaultBRepDrawingCurveLinearizer: BRepDrawingCurveLinearizing {
    public init() {}
    public func linearize(_ curve: OrthographicProjectedCurve, from start: Double, to end: Double,
                          maximumDeviation: Double, usage: inout DrawingExchangeUsage) throws -> BRepDrawingCurvePath {
        try linearize(curve, from: start, to: end, maximumDeviation: maximumDeviation, resources: &usage.resources)
    }

    func linearize(_ curve: OrthographicProjectedCurve, from start: Double, to end: Double,
                   maximumDeviation: Double, resources: inout SharedExchangeResourceAccountant) throws -> BRepDrawingCurvePath {
        guard start.isFinite, end.isFinite, start != end, maximumDeviation.isFinite, maximumDeviation > 0 else {
            throw ExportError.invalidMesh("Invalid original drawing interval or deviation allowance.")
        }
        let owner = resources, limits = owner.limits, tolerance = curve.certificationTolerance
        let admission = try GeometryConversionAdmission(maximumSpanCount: limits.maximumEntities,
            maximumSubdivisionDepth: limits.maximumCurveSubdivisionDepth, remainingSourceDepth: limits.maximumNesting,
            consumeWork: { try owner.charge(work: $0) }, consumeStorage: { try owner.charge(bytes: $0) },
            maximumAlgebraicDepth: limits.maximumAlgebraicDepth)
        let source = try NativeCurveConversionSource(curve.source, tolerance: tolerance, admission: admission)
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
        func station(_ parameter: Double) throws -> (point: Point2D, error: Double) {
            let original = try source.enclosure(over: .init(lower: parameter, upper: parameter),
                tolerance: tolerance, admission: admission)
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
            tolerance: tolerance, admission: admission)
        let first = try station(start)
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
            let pa = try station(a), pb = try station(b)
            pending.append((a, b, pa.point, pb.point, pa.error, pb.error, 0))
        }
        while let (a, b, pa, pb, ea, eb, depth) = pending.popLast() {
            try owner.recordIterations(); try owner.checkTime()
            let span = try ScalarInterval(lower: min(a, b), upper: max(a, b))
            let enclosure = try source.enclosure(over: span, tolerance: tolerance, admission: admission)
            let second = try projected(enclosure.secondDerivative, position: false).lengthUpperBound
            let width = OutwardScalarInterval.exact(span.upper) - .exact(span.lower)
            let error = OutwardScalarInterval.exact(second) * width * width / .exact(8) + .exact(max(ea, eb))
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
                let middle = try station(midpoint)
                try owner.recordEntities(2); try owner.recordBytes(2 * MemoryLayout<Pending>.stride)
                pending.append((midpoint, b, middle.point, pb, middle.error, eb, depth + 1))
                pending.append((a, midpoint, pa, middle.point, ea, middle.error, depth + 1))
            }
        }
        return BRepDrawingCurvePath(curve: curve, startParameter: start, endParameter: end, samples: samples)
    }
}
