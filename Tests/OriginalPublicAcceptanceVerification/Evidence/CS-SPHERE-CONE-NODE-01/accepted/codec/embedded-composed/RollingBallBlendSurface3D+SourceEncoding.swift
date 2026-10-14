import CADCore

/// Encodes original source fields owned by `CADGeometry.RollingBallBlendSurface3D`.
extension CADGeometry.RollingBallBlendSurface3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.RollingBallBlendSurface3D", fields: 5)
        try encoder.field("centerSpine", centerSpine)
        try encoder.field("firstContact", firstContact)
        try encoder.field("radius", radius)
        try encoder.field("secondContact", secondContact)
        try encoder.field("tolerance", tolerance)
    }
}
