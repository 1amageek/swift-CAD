import CADCore

/// Encodes original angular source and symbolic transport, excluding caches.
extension CADGeometry.OriginalAngularTransportSurface3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.OriginalAngularTransportSurface3D", fields: 3)
        try encoder.field("source", source)
        try encoder.field("uTransport", uTransport)
        try encoder.field("vTransport", vTransport)
    }
}
