import CADCore

/// Encodes all original retained STEP placement fields.
extension OriginalSTEPAxis2Placement: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.OriginalSTEPAxis2Placement", fields: 6, using: &admission)
        try encoder.field("adjustments", adjustments, using: &admission)
        try encoder.field("axis", axis, using: &admission)
        try encoder.field("lengthUnit", lengthUnit, using: &admission)
        try encoder.field("location", location, using: &admission)
        try encoder.field("originalLengthSource", originalLengthSource, using: &admission)
        try encoder.field("referenceDirection", referenceDirection, using: &admission)
    }
}
