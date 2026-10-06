import CADCore
import CADGeometry

/// Original ratios, scale presence and model coordinates of a uniform 3D operator.
public struct OriginalSTEPCartesianPlacement: Equatable, Sendable {
    public let originalLengthSource: OriginalSTEPLengthSource?
    public let lengthUnit: LengthUnit
    public let adjustments: [OriginalSTEPPlacementAdjustment]
    public let location: OriginalSTEPPlacementElement
    public let axis1: OriginalSTEPPlacementElement?
    public let axis2: OriginalSTEPPlacementElement?
    public let axis3: OriginalSTEPPlacementElement?
    public let scale: Double?
    public init(lengthUnit: LengthUnit, location: OriginalSTEPPlacementElement,
        axis1: OriginalSTEPPlacementElement?, axis2: OriginalSTEPPlacementElement?,
        axis3: OriginalSTEPPlacementElement?, scale: Double?, adjustments: [OriginalSTEPPlacementAdjustment] = [], originalLengthSource: OriginalSTEPLengthSource? = nil) {
        self.originalLengthSource = originalLengthSource; self.adjustments = adjustments; self.lengthUnit = lengthUnit; self.location = location; self.axis1 = axis1
        self.axis2 = axis2; self.axis3 = axis3; self.scale = scale
    }
}
#if !hasFeature(Embedded)
extension OriginalSTEPCartesianPlacement: Codable {
    private enum Keys: String, CodingKey { case originalLengthSource, lengthUnit, adjustments, location, axis1, axis2, axis3, scale }
    public init(from decoder: Decoder) throws {
        try OriginalSTEPPlacementDecoding.admitRecord(from: decoder, work: 8)
        let object = try decoder.container(keyedBy: Keys.self)
        try object.validateOnlyExpectedKeys([.originalLengthSource, .lengthUnit, .adjustments, .location, .axis1, .axis2, .axis3, .scale], in: decoder)
        originalLengthSource = try object.decode(OriginalSTEPLengthSource?.self, forKey: .originalLengthSource)
        adjustments = try OriginalSTEPPlacementDecoding.adjustments(from: object.superDecoder(forKey: .adjustments))
        lengthUnit = try object.decode(LengthUnit.self, forKey: .lengthUnit)
        location = try object.decode(OriginalSTEPPlacementElement.self, forKey: .location)
        axis1 = try object.decode(OriginalSTEPPlacementElement?.self, forKey: .axis1)
        axis2 = try object.decode(OriginalSTEPPlacementElement?.self, forKey: .axis2)
        axis3 = try object.decode(OriginalSTEPPlacementElement?.self, forKey: .axis3)
        scale = try object.decode(Double?.self, forKey: .scale)
    }
    public func encode(to encoder: Encoder) throws {
        var object = encoder.container(keyedBy: Keys.self)
        try object.encode(originalLengthSource, forKey: .originalLengthSource)
        try object.encode(adjustments, forKey: .adjustments)
        try object.encode(lengthUnit, forKey: .lengthUnit); try object.encode(location, forKey: .location)
        try object.encode(axis1, forKey: .axis1); try object.encode(axis2, forKey: .axis2)
        try object.encode(axis3, forKey: .axis3); try object.encode(scale, forKey: .scale)
    }
}
#endif
