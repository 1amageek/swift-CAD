#if !hasFeature(Embedded)
import CADCore

extension OriginalPolylineCurve3D: Codable {
    private enum CodingKeys: String, CodingKey { case points, isClosed, certificationTolerance }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.points, .isClosed, .certificationTolerance], in: decoder)
            try OriginalAffineWordDecodingContext.validateSourceNesting(from: decoder)
            var usage = try NativeRationalSourceDecodingContext.execution(from: decoder)
            var input = try c.superDecoder(forKey: .points).unkeyedContainer()
            var points: [Point3D] = []
            while !input.isAtEnd {
                try usage.consumeWork(1)
                if points.count == points.capacity {
                    let doubled = points.capacity.multipliedReportingOverflow(by: 2)
                    guard !doubled.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original polyline decode capacity overflows.") }
                    let capacity = points.capacity == 0 ? 1 : doubled.partialValue
                    guard capacity > points.capacity else { throw GeometryConversionError.resourceLimitExceeded("Original polyline decode capacity overflows.") }
                    try RationalAlgebraStorage.retain(capacity, of: Point3D.self, usage: &usage)
                    try usage.consumeWork(points.count); points.reserveCapacity(capacity)
                }
                points.append(try input.decode(Point3D.self))
            }
            let depth = try OriginalAffineWordDecodingContext.maximumSourceDepth(from: decoder) - decoder.codingPath.count
            try self.init(points: points, isClosed: c.decode(Bool.self, forKey: .isClosed),
                tolerance: c.decode(ModelingTolerance.self, forKey: .certificationTolerance),
                remainingSourceDepth: depth, maximumSubdivisionDepth: 0,
                maximumAlgebraicDepth: usage.limits.maximumValueDepth, usage: &usage)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(points, forKey: .points); try c.encode(isClosed, forKey: .isClosed)
        try c.encode(certificationTolerance, forKey: .certificationTolerance)
    }
}
#endif
