import CADCore

/// Encodes all original retained STEP placement fields.
extension OriginalSTEPCartesianPlacement: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.OriginalSTEPCartesianPlacement", fields: 8, using: &admission)
        try encoder.field("adjustments", adjustments, using: &admission)
        try encoder.field("axis1", axis1, using: &admission)
        try encoder.field("axis2", axis2, using: &admission)
        try encoder.field("axis3", axis3, using: &admission)
        try encoder.field("lengthUnit", lengthUnit, using: &admission)
        try encoder.field("location", location, using: &admission)
        try encoder.field("originalLengthSource", originalLengthSource, using: &admission)
        try encoder.field("scale", scale, using: &admission)
    }
}
