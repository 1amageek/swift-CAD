import CADCore
import CADGeometry

/// Encodes original angular source and symbolic transport, excluding caches.
extension CADGeometry.OriginalAngularTransportCurve3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.OriginalAngularTransportCurve3D", fields: 2)
        try encoder.field("source", source)
        try encoder.field("transport", transport)
    }
}
