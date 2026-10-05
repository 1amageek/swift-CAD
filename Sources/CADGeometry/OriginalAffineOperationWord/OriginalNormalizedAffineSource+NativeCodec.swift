#if !hasFeature(Embedded)
import CADCore
extension OriginalNormalizedAffineSource: Codable {
    private enum Keys: String, CodingKey { case family, location, axis1, axis2, axis3, scale, lengthGain, linearGain, adjustments }
    public init(from decoder: any Decoder) throws {
        guard #available(macOS 15.0, iOS 18.0, visionOS 2.0, watchOS 11.0, tvOS 18.0, *) else {
            throw NativeRationalSourceDecodingError.synchronizationCapabilityUnavailable
        }
        var usage = try NativeRationalSourceDecodingContext.allowance(from: decoder)
        try OriginalAffineWordDecodingContext.validateSourceNesting(from: decoder)
        try usage.visitExactCell(depth: 0)
        try NativeOriginalAffineWordCodec.keys(decoder, allowed: ["family", "location", "axis1", "axis2", "axis3", "scale", "lengthGain", "linearGain", "adjustments"])
        let object = try decoder.container(keyedBy: Keys.self)
        for key in [Keys.axis1, .axis2, .axis3, .scale] {
            guard object.contains(key) else {
                throw DecodingError.keyNotFound(key, .init(codingPath: decoder.codingPath,
                    debugDescription: "Original normalized nullable fields must be present."))
            }
        }
        try NativeOriginalAffineWordCodec.vector(object.superDecoder(forKey: .location))
        for key in [Keys.axis1, .axis2, .axis3] {
            if try !object.decodeNil(forKey: key) {
                try NativeOriginalAffineWordCodec.vector(object.superDecoder(forKey: key))
            }
        }
        let tag = try object.decode(String.self, forKey: .family)
        guard let family = Family(rawValue: tag) else {
            throw DecodingError.dataCorruptedError(forKey: .family, in: object,
                debugDescription: "Unknown original normalized family.")
        }
        var container = try object.nestedUnkeyedContainer(forKey: .adjustments)
        guard let count = container.count else { throw NativeRationalSourceDecodingError.unboundedWordContainer }
        try usage.consumeExactWork(count)
        try OriginalAffineRationalMatrix.retain(count, of: OriginalNormalizedAffineAdjustment.self, usage: &usage)
        var adjustments: [OriginalNormalizedAffineAdjustment] = []; adjustments.reserveCapacity(count)
        while !container.isAtEnd {
            let item = try container.superDecoder()
            try NativeOriginalAffineWordCodec.keys(item, allowed: ["displacement", "conjugates"])
            let value = try item.container(keyedBy: AdjustmentKeys.self)
            try NativeOriginalAffineWordCodec.vector(value.superDecoder(forKey: .displacement))
            adjustments.append(try OriginalNormalizedAffineAdjustment(from: item))
        }
        self.init(family: family, location: try object.decode(Vector3D.self, forKey: .location),
            axis1: try object.decodeIfPresent(Vector3D.self, forKey: .axis1),
            axis2: try object.decodeIfPresent(Vector3D.self, forKey: .axis2),
            axis3: try object.decodeIfPresent(Vector3D.self, forKey: .axis3),
            scale: try object.decodeIfPresent(Double.self, forKey: .scale),
            lengthGain: try object.decode(ExactRationalCoefficient.self, forKey: .lengthGain),
            linearGain: try object.decode(ExactRationalCoefficient.self, forKey: .linearGain), adjustments: adjustments)
    }
    private enum AdjustmentKeys: String, CodingKey { case displacement, conjugates }
    public func encode(to encoder: any Encoder) throws {
        var object = encoder.container(keyedBy: Keys.self)
        try object.encode(family.rawValue, forKey: .family); try object.encode(location, forKey: .location)
        try object.encode(axis1, forKey: .axis1); try object.encode(axis2, forKey: .axis2)
        try object.encode(axis3, forKey: .axis3); try object.encode(scale, forKey: .scale)
        try object.encode(linearGain, forKey: .linearGain)
        try object.encode(lengthGain, forKey: .lengthGain); try object.encode(adjustments, forKey: .adjustments)
    }
}
#endif
