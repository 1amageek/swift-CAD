import CADCore

/// Encodes the entire original foreign length-source authority.
extension OriginalSTEPLengthSource: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.OriginalSTEPLengthSource", fields: 2, using: &admission)
        try encoder.field("id", id, using: &admission)
        try encoder.field("law", law, using: &admission)
    }
}
