#if !hasFeature(Embedded)
extension OriginalAffineOperation: Codable {
    private enum Keys: String, CodingKey { case operation, transform, source }
    private enum FrameKeys: String, CodingKey { case basisX, basisY, basisZ, translation }
    public init(from decoder: any Decoder) throws {
        let object = try decoder.container(keyedBy: Keys.self)
        let operation = try object.decode(String.self, forKey: .operation)
        switch operation {
        case "forward", "inverse":
            try NativeOriginalAffineWordCodec.keys(decoder, allowed: ["operation", "transform"])
            let source = try object.superDecoder(forKey: .transform)
            try NativeOriginalAffineWordCodec.keys(source, allowed: ["basisX", "basisY", "basisZ", "translation"])
            let frame = try source.container(keyedBy: FrameKeys.self)
            for key in [FrameKeys.basisX, .basisY, .basisZ, .translation] {
                try NativeOriginalAffineWordCodec.vector(frame.superDecoder(forKey: key))
            }
            let value = try AffineTransform3D(from: source)
            self = operation == "forward" ? .forward(value) : .inverse(value)
        case "rationalForward", "rationalInverse":
            try NativeOriginalAffineWordCodec.keys(decoder, allowed: ["operation", "source"])
            let value = try object.decode(OriginalRationalAffineSource.self, forKey: .source)
            self = operation == "rationalForward" ? .rationalForward(value) : .rationalInverse(value)
        case "normalizedForward", "normalizedInverse":
            try NativeOriginalAffineWordCodec.keys(decoder, allowed: ["operation", "source"])
            let value = try object.decode(OriginalNormalizedAffineSource.self, forKey: .source)
            self = operation == "normalizedForward" ? .normalizedForward(value) : .normalizedInverse(value)
        default:
            throw DecodingError.dataCorruptedError(forKey: .operation, in: object,
                debugDescription: "Unknown original affine operation.")
        }
    }
    public func encode(to encoder: any Encoder) throws {
        var object = encoder.container(keyedBy: Keys.self)
        switch self {
        case .forward(let value):
            try object.encode("forward", forKey: .operation); try object.encode(value, forKey: .transform)
        case .inverse(let value):
            try object.encode("inverse", forKey: .operation); try object.encode(value, forKey: .transform)
        case .rationalForward(let value):
            try object.encode("rationalForward", forKey: .operation); try object.encode(value, forKey: .source)
        case .rationalInverse(let value):
            try object.encode("rationalInverse", forKey: .operation); try object.encode(value, forKey: .source)
        case .normalizedForward(let value):
            try object.encode("normalizedForward", forKey: .operation); try object.encode(value, forKey: .source)
        case .normalizedInverse(let value):
            try object.encode("normalizedInverse", forKey: .operation); try object.encode(value, forKey: .source)
        }
    }
}
#endif
