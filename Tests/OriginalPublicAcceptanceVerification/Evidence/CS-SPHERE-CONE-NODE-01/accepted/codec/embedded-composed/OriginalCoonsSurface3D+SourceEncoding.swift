import CADCore

/// Encodes the four original traversals without derived corner caches.
extension CADGeometry.OriginalCoonsSurface3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.OriginalCoonsSurface3D", fields: 4)
        try encoder.field("uMaximumBoundary", uMaximumBoundary)
        try encoder.field("uMinimumBoundary", uMinimumBoundary)
        try encoder.field("vMaximumBoundary", vMaximumBoundary)
        try encoder.field("vMinimumBoundary", vMinimumBoundary)
    }
}
