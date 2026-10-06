import CADCore
import CADGeometry

/// Original conversion unit fields and shared standard measure/dimension identities.
public struct IndependentShapeAngularConversion: Equatable, Sendable {
    public enum Interpretation: String, Sendable { case binary, canonicalDegree }
    public enum MeasureKind: String, Sendable { case measureWithUnit, planeAngleMeasureWithUnit, complexPlaneAngleMeasureWithUnit }
    public let name: String
    public let factor: Double
    public let interpretation: Interpretation
    public let dimensionsID: IndependentShapeAngularDimensionsID
    public let dimensions: [Double]
    public let measureID: IndependentShapeAngularMeasureID
    public let measureKind: MeasureKind
    public let base: IndependentShapeAngularSource
    public init(name: String, factor: Double, interpretation: Interpretation,
        dimensionsID: IndependentShapeAngularDimensionsID = .init(), dimensions: [Double] = [0,0,0,0,0,0,0],
        measureID: IndependentShapeAngularMeasureID = .init(), measureKind: MeasureKind = .planeAngleMeasureWithUnit,
        base: IndependentShapeAngularSource) {
        self.name = name; self.factor = factor; self.interpretation = interpretation
        self.dimensionsID = dimensionsID; self.dimensions = dimensions; self.measureID = measureID
        self.measureKind = measureKind; self.base = base
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name.utf8.elementsEqual(rhs.name.utf8) && lhs.factor == rhs.factor && lhs.interpretation == rhs.interpretation
            && lhs.dimensionsID == rhs.dimensionsID && lhs.dimensions == rhs.dimensions && lhs.measureID == rhs.measureID
            && lhs.measureKind == rhs.measureKind && lhs.base == rhs.base
    }
#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case name, factor, interpretation, dimensionsID, dimensions, measureID, measureKind, base }
    public init(from decoder: Decoder) throws {
        guard #available(macOS 15.0, iOS 18.0, visionOS 2.0, watchOS 11.0, tvOS 18.0, *) else { throw NativeRationalSourceDecodingError.synchronizationCapabilityUnavailable }
        let allowance = try NativeRationalSourceDecodingContext.allowance(from: decoder)
        try OriginalAffineWordDecodingContext.validateSourceNesting(from: decoder)
        try allowance.visitExactCell(depth: 0)
        try allowance.consumeExactWork(8)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.name, .factor, .interpretation, .dimensionsID, .dimensions, .measureID, .measureKind, .base], in: decoder)
        name = try c.decode(String.self, forKey: .name); factor = try c.decode(Double.self, forKey: .factor)
        interpretation = try c.decode(Interpretation.self, forKey: .interpretation)
        dimensionsID = try c.decode(IndependentShapeAngularDimensionsID.self, forKey: .dimensionsID)
        var values = try c.nestedUnkeyedContainer(forKey: .dimensions)
        guard values.count == 7 else { throw IndependentShapeSourceError.invalidSource("Original angular dimensions require exactly seven exponents.") }
        try allowance.consumeExactWork(7); try allowance.retainExactStorage(7)
        var originalDimensions: [Double] = []; originalDimensions.reserveCapacity(7)
        while !values.isAtEnd { originalDimensions.append(try values.decode(Double.self)) }
        dimensions = originalDimensions
        measureID = try c.decode(IndependentShapeAngularMeasureID.self, forKey: .measureID)
        measureKind = try c.decode(MeasureKind.self, forKey: .measureKind); base = try c.decode(IndependentShapeAngularSource.self, forKey: .base)
    }
#endif
}
#if !hasFeature(Embedded)
extension IndependentShapeAngularConversion: Codable {}
extension IndependentShapeAngularConversion.Interpretation: Codable {}
extension IndependentShapeAngularConversion.MeasureKind: Codable {}
#endif
