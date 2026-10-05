import CADCore

/// Encodes the entire original foreign length-source authority.
extension OriginalSTEPLengthSource: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.OriginalSTEPLengthSource", fields: 2)
        try encoder.field("id", id)
        try encoder.field("law", law)
    }
}
