import CADCore
import CADGeometry

/// Original model coordinates and proposed axes of AXIS2_PLACEMENT_3D.
public struct OriginalSTEPAxis2Placement: Equatable, Sendable {
    public let originalLengthSource: OriginalSTEPLengthSource?
    public let lengthUnit: LengthUnit
    public let adjustments: [OriginalSTEPPlacementAdjustment]
    public let location: OriginalSTEPPlacementElement
    public let axis: OriginalSTEPPlacementElement?
    public let referenceDirection: OriginalSTEPPlacementElement?
    public init(lengthUnit: LengthUnit, location: OriginalSTEPPlacementElement,
        axis: OriginalSTEPPlacementElement?, referenceDirection: OriginalSTEPPlacementElement?, adjustments: [OriginalSTEPPlacementAdjustment] = [], originalLengthSource: OriginalSTEPLengthSource? = nil) {
        self.originalLengthSource = originalLengthSource; self.adjustments = adjustments; self.lengthUnit = lengthUnit; self.location = location
        self.axis = axis; self.referenceDirection = referenceDirection
    }
}
#if !hasFeature(Embedded)
extension OriginalSTEPAxis2Placement: Codable {
    private enum Keys: String, CodingKey { case originalLengthSource, lengthUnit, adjustments, location, axis, referenceDirection }
    public init(from decoder: Decoder) throws {
        try OriginalSTEPPlacementDecoding.admitRecord(from: decoder, work: 6)
        let object = try decoder.container(keyedBy: Keys.self)
        try object.validateOnlyExpectedKeys([.originalLengthSource, .lengthUnit, .adjustments, .location, .axis, .referenceDirection], in: decoder)
        originalLengthSource = try object.decode(OriginalSTEPLengthSource?.self, forKey: .originalLengthSource)
        adjustments = try OriginalSTEPPlacementDecoding.adjustments(from: object.superDecoder(forKey: .adjustments))
        lengthUnit = try object.decode(LengthUnit.self, forKey: .lengthUnit)
        location = try object.decode(OriginalSTEPPlacementElement.self, forKey: .location)
        axis = try object.decode(OriginalSTEPPlacementElement?.self, forKey: .axis)
        referenceDirection = try object.decode(OriginalSTEPPlacementElement?.self, forKey: .referenceDirection)
    }
    public func encode(to encoder: Encoder) throws {
        var object = encoder.container(keyedBy: Keys.self)
        try object.encode(originalLengthSource, forKey: .originalLengthSource)
        try object.encode(adjustments, forKey: .adjustments)
        try object.encode(lengthUnit, forKey: .lengthUnit); try object.encode(location, forKey: .location)
        try object.encode(axis, forKey: .axis); try object.encode(referenceDirection, forKey: .referenceDirection)
    }
}
#endif
