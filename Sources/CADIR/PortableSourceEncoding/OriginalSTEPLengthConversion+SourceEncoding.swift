import CADCore

/// Encodes the entire original foreign length-source authority.
extension OriginalSTEPLengthConversion: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.OriginalSTEPLengthConversion", fields: 7, using: &admission)
        try encoder.field("base", base, using: &admission)
        try encoder.field("dimensions", dimensions, using: &admission)
        try encoder.field("dimensionsID", dimensionsID, using: &admission)
        try encoder.field("factorLiteral", factorLiteral, using: &admission)
        try encoder.field("measureID", measureID, using: &admission)
        try encoder.field("measureKind", measureKind, using: &admission)
        try encoder.field("name", name, using: &admission)
    }
}
