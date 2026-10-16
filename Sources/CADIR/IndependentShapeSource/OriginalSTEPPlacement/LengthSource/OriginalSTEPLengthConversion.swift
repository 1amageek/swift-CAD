import CADCore
import CADGeometry

/// Original standard length conversion and its actual referenced records.
public struct OriginalSTEPLengthConversion: Equatable, Sendable {
    public enum MeasureKind: String, Sendable { case measureWithUnit, lengthMeasureWithUnit, complexLengthMeasureWithUnit }
    public let name: String
    public let dimensionsID: PortableIdentity128
    public let dimensions: [String]
    public let measureID: PortableIdentity128
    public let measureKind: MeasureKind
    public let factorLiteral: String
    public let base: OriginalSTEPLengthSource
    public init(name: String, dimensionsID: PortableIdentity128, dimensions: [String],
        measureID: PortableIdentity128, measureKind: MeasureKind, factorLiteral: String, base: OriginalSTEPLengthSource) {
        self.name = name; self.dimensionsID = dimensionsID; self.dimensions = dimensions
        self.measureID = measureID; self.measureKind = measureKind; self.factorLiteral = factorLiteral; self.base = base
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name.utf8.elementsEqual(rhs.name.utf8) && lhs.dimensionsID == rhs.dimensionsID
            && lhs.dimensions == rhs.dimensions && lhs.measureID == rhs.measureID && lhs.measureKind == rhs.measureKind
            && lhs.factorLiteral.utf8.elementsEqual(rhs.factorLiteral.utf8) && lhs.base == rhs.base
    }
}
#if !hasFeature(Embedded)
extension OriginalSTEPLengthConversion: Codable {
    private enum Keys: String, CodingKey { case name, dimensionsID, dimensions, measureID, measureKind, factorLiteral, base }
    public init(from decoder: Decoder) throws {
        guard #available(macOS 15.0, iOS 18.0, visionOS 2.0, watchOS 11.0, tvOS 18.0, *) else { throw NativeRationalSourceDecodingError.synchronizationCapabilityUnavailable }
        var usage = try NativeRationalSourceDecodingContext.execution(from: decoder)
        try OriginalAffineWordDecodingContext.validateSourceNesting(from: decoder)
        try usage.visitCell(axis: .value, depth: 0)
        let c = try decoder.container(keyedBy: Keys.self)
        try c.validateOnlyExpectedKeys([.name, .dimensionsID, .dimensions, .measureID, .measureKind, .factorLiteral, .base], in: decoder)
        name = try c.decode(String.self, forKey: .name); dimensionsID = try OriginalSTEPIdentityCoding.decode(from: c.superDecoder(forKey: .dimensionsID))
        var source = try c.nestedUnkeyedContainer(forKey: .dimensions)
        guard source.count == 7 else { throw IndependentShapeSourceError.invalidSource("Original length dimensions require seven exponents.") }
        try usage.consumeWork(7); try RationalAlgebraStorage.retain(7 * MemoryLayout<String>.stride / MemoryLayout<UInt32>.stride, of: UInt32.self, usage: &usage)
        var values: [String] = []; values.reserveCapacity(7)
        while !source.isAtEnd { values.append(try source.decode(String.self)) }
        dimensions = values; measureID = try OriginalSTEPIdentityCoding.decode(from: c.superDecoder(forKey: .measureID))
        measureKind = try c.decode(MeasureKind.self, forKey: .measureKind); factorLiteral = try c.decode(String.self, forKey: .factorLiteral)
        base = try c.decode(OriginalSTEPLengthSource.self, forKey: .base)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(name, forKey: .name)
        try c.encode(dimensionsID.canonicalString, forKey: .dimensionsID)
        try c.encode(dimensions, forKey: .dimensions)
        try c.encode(measureID.canonicalString, forKey: .measureID)
        try c.encode(measureKind, forKey: .measureKind)
        try c.encode(factorLiteral, forKey: .factorLiteral)
        try c.encode(base, forKey: .base)
    }
}
extension OriginalSTEPLengthConversion.MeasureKind: Codable {}
#endif
