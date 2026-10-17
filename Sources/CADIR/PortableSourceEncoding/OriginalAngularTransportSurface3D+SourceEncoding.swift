import CADCore
import CADGeometry

/// Encodes original angular source and symbolic transport, excluding caches.
extension CADGeometry.OriginalAngularTransportSurface3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.OriginalAngularTransportSurface3D", fields: 3, using: &admission)
        try encoder.field("source", source, using: &admission)
        try encoder.field("uTransport", uTransport, using: &admission)
        try encoder.field("vTransport", vTransport, using: &admission)
    }
}
