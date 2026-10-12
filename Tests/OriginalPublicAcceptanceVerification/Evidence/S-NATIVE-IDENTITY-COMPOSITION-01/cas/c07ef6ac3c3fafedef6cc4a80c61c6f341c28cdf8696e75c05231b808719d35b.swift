/// Encodes original source fields owned by `CADCore.Quantity`.
extension CADCore.Quantity: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADCore.Quantity", fields: 2)
        try encoder.field("kind", kind)
        try encoder.field("value", value)
    }
}
