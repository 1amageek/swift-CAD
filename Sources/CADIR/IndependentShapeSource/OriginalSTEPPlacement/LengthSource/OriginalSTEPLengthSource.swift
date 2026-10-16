import CADCore
import CADGeometry

/// Original foreign length-unit graph, separate from native binary unit conventions.
public struct OriginalSTEPLengthSource: Equatable, Sendable {
    public indirect enum Law: Equatable, Sendable {
        case metre(prefix: IndependentShapeSIPrefix?)
        case conversion(OriginalSTEPLengthConversion)
    }
    public let id: PortableIdentity128
    public let law: Law
    public init(id: PortableIdentity128, law: Law) { self.id = id; self.law = law }
    public func exactGain(maximumDepth: Int, using execution: inout OriginalQueryExecution) throws -> ExactRationalCoefficient {
        try gain(depth: 0, maximumDepth: maximumDepth, using: &execution)
    }
    private func gain(depth: Int, maximumDepth: Int, using execution: inout OriginalQueryExecution) throws -> ExactRationalCoefficient {
        if depth > maximumDepth { throw IndependentShapeSourceError.resourceLimitExceeded("Original length chain exceeds the caller depth.") }
        try execution.visitCell(axis: .value, depth: 0)
        switch law {
        case .metre(let prefix): return try OriginalSTEPDecimal.powerOfTen(prefix?.decimalExponent ?? 0, using: &execution)
        case .conversion(let source):
            try execution.consumeWork(source.name.utf8.count + 1)
            guard source.dimensions.count == 7 else { throw IndependentShapeSourceError.invalidSource("Original length dimensions require seven exponents.") }
            for index in source.dimensions.indices {
                let value = try OriginalSTEPDecimal.coefficient(source.dimensions[index], using: &execution)
                guard value == (index == 0 ? .one : .zero) else { throw IndependentShapeSourceError.invalidSource("Original conversion dimensions are not length dimensions.") }
            }
            let factor = try OriginalSTEPDecimal.coefficient(source.factorLiteral, using: &execution)
            guard factor.isPositive else { throw IndependentShapeSourceError.invalidSource("Original length conversion factor is not positive.") }
            return try factor.multiplied(by: source.base.gain(depth: depth + 1, maximumDepth: maximumDepth, using: &execution), usage: &execution)
        }
    }
}
#if !hasFeature(Embedded)
extension OriginalSTEPLengthSource: Codable {
    private enum Keys: String, CodingKey { case id, law }
    public init(from decoder: Decoder) throws {
        guard #available(macOS 15.0, iOS 18.0, visionOS 2.0, watchOS 11.0, tvOS 18.0, *) else { throw NativeRationalSourceDecodingError.synchronizationCapabilityUnavailable }
        var usage = try NativeRationalSourceDecodingContext.execution(from: decoder)
        try OriginalAffineWordDecodingContext.validateSourceNesting(from: decoder)
        try usage.visitCell(axis: .value, depth: 0)
        let c = try decoder.container(keyedBy: Keys.self)
        try c.validateOnlyExpectedKeys([.id, .law], in: decoder)
        id = try OriginalSTEPIdentityCoding.decode(from: c.superDecoder(forKey: .id)); law = try c.decode(Law.self, forKey: .law)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(id.canonicalString, forKey: .id)
        try c.encode(law, forKey: .law)
    }
}
extension OriginalSTEPLengthSource.Law: Codable {
    private enum Keys: String, CodingKey { case kind, prefix, conversion }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "metre": try c.validateOnlyExpectedKeys([.kind, .prefix], in: decoder); self = .metre(prefix: try c.decode(IndependentShapeSIPrefix?.self, forKey: .prefix))
        case "conversion": try c.validateOnlyExpectedKeys([.kind, .conversion], in: decoder); self = .conversion(try c.decode(OriginalSTEPLengthConversion.self, forKey: .conversion))
        default: throw IndependentShapeSourceError.invalidSource("Unknown original length-unit law.")
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .metre(let prefix): try c.encode("metre", forKey: .kind); try c.encode(prefix, forKey: .prefix)
        case .conversion(let source): try c.encode("conversion", forKey: .kind); try c.encode(source, forKey: .conversion)
        }
    }
}
#endif
