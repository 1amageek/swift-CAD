import CADCore
import CADGeometry

/// Retains complete original image authority and excludes prepared caches.
extension OriginalAffineWordSurface3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.OriginalAffineWordSurface3D", fields: 2, using: &admission)
        try encoder.field("operationWord", operationWord, using: &admission)
        try encoder.field("source", source, using: &admission)
    }
}
