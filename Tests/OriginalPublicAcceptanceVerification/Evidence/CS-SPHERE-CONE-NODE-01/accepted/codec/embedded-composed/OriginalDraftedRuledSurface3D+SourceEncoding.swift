import CADCore

/// Encodes original draft source values, excluding derived preparation caches.
extension CADGeometry.OriginalDraftedRuledSurface3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.OriginalDraftedRuledSurface3D", fields: 2)
        try encoder.field("endHeight", endHeight)
        try encoder.field("start", start)
    }
}
