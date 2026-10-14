import CADCore

/// Encodes original source fields owned by `CADGeometry.Circle3D`.
extension CADGeometry.Circle3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.Circle3D", fields: 3)
        try encoder.field("center", center)
        try encoder.field("normal", normal)
        try encoder.field("radius", radius)
    }
}
