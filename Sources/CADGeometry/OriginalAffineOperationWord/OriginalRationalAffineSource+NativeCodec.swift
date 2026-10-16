#if !hasFeature(Embedded)
import CADCore

extension OriginalRationalAffineSource: Codable {
    private enum Keys: String, CodingKey { case coefficients }
    public init(from decoder: any Decoder) throws {
        guard #available(macOS 15.0, iOS 18.0, visionOS 2.0, watchOS 11.0, tvOS 18.0, *) else {
            throw NativeRationalSourceDecodingError.synchronizationCapabilityUnavailable
        }
        try NativeOriginalAffineWordCodec.keys(decoder, allowed: ["coefficients"])
        var usage = try NativeRationalSourceDecodingContext.execution(from: decoder)
        try usage.visitCell(axis: .coefficient, depth: 0)
        let object = try decoder.container(keyedBy: Keys.self)
        var array = try object.nestedUnkeyedContainer(forKey: .coefficients)
        guard array.count == 12 else {
            throw DecodingError.dataCorruptedError(forKey: .coefficients, in: object,
                debugDescription: "Original rational affine source requires exactly twelve coefficients.")
        }
        try OriginalAffineRationalMatrix.retain(12, of: ExactRationalCoefficient.self, usage: &usage)
        var values: [ExactRationalCoefficient] = []; values.reserveCapacity(12)
        while !array.isAtEnd {
            let source = try array.superDecoder()
            try NativeOriginalAffineWordCodec.keys(source, allowed: ["sign", "numeratorWords", "denominatorWords"])
            values.append(try ExactRationalCoefficient(from: source))
        }
        try self.init(coefficients: values, usage: &usage)
    }
    public func encode(to encoder: any Encoder) throws {
        var object = encoder.container(keyedBy: Keys.self)
        try object.encode(coefficients, forKey: .coefficients)
    }
}
#endif
