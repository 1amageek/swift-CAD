/// Encodes original source fields owned by `CADCore.Vector3D`.
extension CADCore.Vector3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADCore.Vector3D", fields: 3)
        try encoder.field("x", x)
        try encoder.field("y", y)
        try encoder.field("z", z)
    }
}
