/// Encodes original source fields owned by `CADCore.Point3D`.
extension CADCore.Point3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADCore.Point3D", fields: 3)
        try encoder.field("x", x)
        try encoder.field("y", y)
        try encoder.field("z", z)
    }
}
