import CADCore

/// Encodes all original retained STEP placement fields.
extension OriginalSTEPAxis2Placement: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.OriginalSTEPAxis2Placement", fields: 6)
        try encoder.field("adjustments", adjustments)
        try encoder.field("axis", axis)
        try encoder.field("lengthUnit", lengthUnit)
        try encoder.field("location", location)
        try encoder.field("originalLengthSource", originalLengthSource)
        try encoder.field("referenceDirection", referenceDirection)
    }
}
