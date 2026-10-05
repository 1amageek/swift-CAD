import CADCore

/// Encodes all original retained STEP placement fields.
extension OriginalSTEPCartesianPlacement: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.OriginalSTEPCartesianPlacement", fields: 8)
        try encoder.field("adjustments", adjustments)
        try encoder.field("axis1", axis1)
        try encoder.field("axis2", axis2)
        try encoder.field("axis3", axis3)
        try encoder.field("lengthUnit", lengthUnit)
        try encoder.field("location", location)
        try encoder.field("originalLengthSource", originalLengthSource)
        try encoder.field("scale", scale)
    }
}
