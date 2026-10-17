/// Encodes original source fields owned by `CADCore.SubshapeID`.
extension CADCore.SubshapeID: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADCore.SubshapeID", fields: 3, using: &admission)
        try encoder.field("featureID", featureID, using: &admission)
        try encoder.field("ordinal", ordinal, using: &admission)
        try encoder.field("role", role, using: &admission)
    }
}
