/// Encodes original source fields owned by `CADCore.UnitSystem`.
extension CADCore.UnitSystem: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADCore.UnitSystem", fields: 2)
        try encoder.field("angle", angle)
        try encoder.field("length", length)
    }
}
