/// Encodes original source fields owned by `CADCore.SubshapeID`.
extension CADCore.SubshapeID: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADCore.SubshapeID", fields: 3)
        try encoder.field("featureID", featureID)
        try encoder.field("ordinal", ordinal)
        try encoder.field("role", role)
    }
}
