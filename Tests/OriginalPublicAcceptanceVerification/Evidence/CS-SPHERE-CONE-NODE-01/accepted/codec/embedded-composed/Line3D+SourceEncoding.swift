import CADCore

/// Encodes original source fields owned by `CADGeometry.Line3D`.
extension CADGeometry.Line3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.Line3D", fields: 2)
        try encoder.field("direction", direction)
        try encoder.field("origin", origin)
    }
}
