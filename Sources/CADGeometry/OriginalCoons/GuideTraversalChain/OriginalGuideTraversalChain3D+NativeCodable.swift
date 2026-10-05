#if !hasFeature(Embedded)
import CADCore

extension OriginalGuideTraversalChain3D: Codable {
    private enum CodingKeys: String, CodingKey { case traversals, stations, sourceSegmentOrdinals }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.traversals, .stations, .sourceSegmentOrdinals], in: decoder)
        if #available(macOS 15, iOS 18, visionOS 2, watchOS 11, tvOS 18, *) {
            try OriginalAffineWordDecodingContext.validateSourceNesting(from: decoder)
            var usage = try NativeRationalSourceDecodingContext.allowance(from: decoder)
            func values<T: Decodable>(_ key: CodingKeys, as type: T.Type) throws -> [T] {
                var input = try c.superDecoder(forKey: key).unkeyedContainer()
                var result: [T] = []
                while !input.isAtEnd {
                    try usage.consumeExactWork(1)
                    if result.count == result.capacity {
                        let doubled = result.capacity.multipliedReportingOverflow(by: 2)
                        guard !doubled.overflow else {
                            throw GeometryConversionError.resourceLimitExceeded("Original guide decoded array capacity overflows.")
                        }
                        let capacity = result.capacity == 0 ? 1 : doubled.partialValue
                        guard capacity > result.capacity else {
                            throw GeometryConversionError.resourceLimitExceeded("Original guide decoded array capacity overflows.")
                        }
                        try RationalAlgebraStorage.retain(capacity, of: T.self, usage: &usage)
                        try usage.consumeExactWork(result.count)
                        result.reserveCapacity(capacity)
                    }
                    result.append(try input.decode(T.self))
                }
                return result
            }
            let traversals = try values(.traversals, as: OriginalCurveRootSpan3D.self)
            let stations = try values(.stations, as: ExactRationalCoefficient.self)
            let ordinals = try values(.sourceSegmentOrdinals, as: Int.self)
            guard let first = traversals.first else {
                throw GeometryConversionError.invalidInput("Original guide decoded source cannot be empty.")
            }
            let depth = try OriginalAffineWordDecodingContext.maximumSourceDepth(from: decoder) - decoder.codingPath.count
            try self.init(traversals: traversals, stations: stations, sourceSegmentOrdinals: ordinals,
                remainingSourceDepth: depth, tolerance: first.certificationTolerance, usage: &usage)
        } else { throw NativeRationalSourceDecodingError.synchronizationCapabilityUnavailable }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(traversals, forKey: .traversals)
        try c.encode(stations, forKey: .stations)
        try c.encode(sourceSegmentOrdinals, forKey: .sourceSegmentOrdinals)
    }
}
#endif
