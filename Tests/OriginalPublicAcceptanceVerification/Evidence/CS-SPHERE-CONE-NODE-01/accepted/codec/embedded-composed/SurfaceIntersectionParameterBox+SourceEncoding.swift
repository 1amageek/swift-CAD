import CADCore

/// Encodes original source fields owned by `CADGeometry.SurfaceIntersectionParameterBox`.
extension CADGeometry.SurfaceIntersectionParameterBox: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.SurfaceIntersectionParameterBox", fields: 4)
        try encoder.field("firstU", firstU)
        try encoder.field("firstV", firstV)
        try encoder.field("secondU", secondU)
        try encoder.field("secondV", secondV)
    }
}
