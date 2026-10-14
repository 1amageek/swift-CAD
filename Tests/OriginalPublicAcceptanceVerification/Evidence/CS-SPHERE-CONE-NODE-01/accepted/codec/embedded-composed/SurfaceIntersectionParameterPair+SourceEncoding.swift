import CADCore

/// Encodes original source fields owned by `CADGeometry.SurfaceIntersectionParameterPair`.
extension CADGeometry.SurfaceIntersectionParameterPair: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.SurfaceIntersectionParameterPair", fields: 2)
        try encoder.field("first", first)
        try encoder.field("second", second)
    }
}
