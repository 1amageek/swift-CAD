import CADCore
import CADGeometry

/// Encodes original angular source and symbolic transport, excluding caches.
extension CADGeometry.OriginalAngularTransportCurve3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.OriginalAngularTransportCurve3D", fields: 2, using: &admission)
        try encoder.field("source", source, using: &admission)
        try encoder.field("transport", transport, using: &admission)
    }
}
