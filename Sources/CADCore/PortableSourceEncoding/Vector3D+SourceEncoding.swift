/// Encodes original source fields owned by `CADCore.Vector3D`.
extension CADCore.Vector3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADCore.Vector3D", fields: 3, using: &admission)
        try encoder.field("x", x, using: &admission)
        try encoder.field("y", y, using: &admission)
        try encoder.field("z", z, using: &admission)
    }
}
