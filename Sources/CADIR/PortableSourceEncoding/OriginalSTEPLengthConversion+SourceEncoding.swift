import CADCore

/// Encodes the entire original foreign length-source authority.
extension OriginalSTEPLengthConversion: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.OriginalSTEPLengthConversion", fields: 7)
        try encoder.field("base", base)
        try encoder.field("dimensions", dimensions)
        try encoder.field("dimensionsID", dimensionsID)
        try encoder.field("factorLiteral", factorLiteral)
        try encoder.field("measureID", measureID)
        try encoder.field("measureKind", measureKind)
        try encoder.field("name", name)
    }
}
