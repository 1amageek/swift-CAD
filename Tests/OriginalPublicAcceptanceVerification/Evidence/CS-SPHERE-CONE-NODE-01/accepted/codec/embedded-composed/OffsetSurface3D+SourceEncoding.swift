import CADCore

/// Encodes original source fields owned by `CADGeometry.OffsetSurface3D`.
extension CADGeometry.OffsetSurface3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.OffsetSurface3D", fields: 2)
        try encoder.field("distance", distance)
        try encoder.field("source", source)
    }
}
