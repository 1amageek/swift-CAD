import CADCore
import CADGeometry

/// Original foreign angular unit graph; identity and exact conversion law are retained.
public struct IndependentShapeAngularSource: Equatable, Sendable {
    public indirect enum Law: Equatable, Sendable {
        case radian(prefix: IndependentShapeSIPrefix?)
        case conversion(IndependentShapeAngularConversion)
    }
    public let id: IndependentShapeAngularUnitID
    public let law: Law
    public init(id: IndependentShapeAngularUnitID = .init(), law: Law) { self.id = id; self.law = law }
#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case id, law }
    public init(from decoder: Decoder) throws {
        guard #available(macOS 15.0, iOS 18.0, visionOS 2.0, watchOS 11.0, tvOS 18.0, *) else { throw NativeRationalSourceDecodingError.synchronizationCapabilityUnavailable }
        let allowance = try NativeRationalSourceDecodingContext.allowance(from: decoder)
        try OriginalAffineWordDecodingContext.validateSourceNesting(from: decoder)
        try allowance.visitExactCell(depth: 0)
        try allowance.consumeExactWork(8)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.id, .law], in: decoder)
        id = try c.decode(IndependentShapeAngularUnitID.self, forKey: .id); law = try c.decode(Law.self, forKey: .law)
    }
#endif
}
#if !hasFeature(Embedded)
extension IndependentShapeAngularSource: Codable {}
extension IndependentShapeAngularSource.Law: Codable {
    private enum CodingKeys: String, CodingKey { case kind, prefix, conversion }
    public init(from decoder: Decoder) throws {
        guard #available(macOS 15.0, iOS 18.0, visionOS 2.0, watchOS 11.0, tvOS 18.0, *) else { throw NativeRationalSourceDecodingError.synchronizationCapabilityUnavailable }
        let allowance = try NativeRationalSourceDecodingContext.allowance(from: decoder)
        try OriginalAffineWordDecodingContext.validateSourceNesting(from: decoder)
        try allowance.visitExactCell(depth: 0)
        try allowance.consumeExactWork(8)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "radian":
            try c.validateOnlyExpectedKeys([.kind, .prefix], in: decoder)
            self = .radian(prefix: try c.decode(IndependentShapeSIPrefix?.self, forKey: .prefix))
        case "conversion":
            try c.validateOnlyExpectedKeys([.kind, .conversion], in: decoder)
            self = .conversion(try c.decode(IndependentShapeAngularConversion.self, forKey: .conversion))
        default: throw IndependentShapeSourceError.invalidSource("Unknown original angular unit law.")
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .radian(let prefix): try c.encode("radian", forKey: .kind); try c.encode(prefix, forKey: .prefix)
        case .conversion(let value): try c.encode("conversion", forKey: .kind); try c.encode(value, forKey: .conversion)
        }
    }
}
#endif
