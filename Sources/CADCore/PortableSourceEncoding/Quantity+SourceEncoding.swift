/// Encodes original source fields owned by `CADCore.Quantity`.
extension CADCore.Quantity: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADCore.Quantity", fields: 2, using: &admission)
        try encoder.field("kind", kind, using: &admission)
        try encoder.field("value", value, using: &admission)
    }
}
