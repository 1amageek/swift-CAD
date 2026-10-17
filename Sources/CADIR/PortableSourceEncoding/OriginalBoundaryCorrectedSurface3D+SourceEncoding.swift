import CADCore
import CADGeometry

/// Encodes the complete authored final support source, excluding preparation caches.
extension CADGeometry.OriginalBoundaryCorrectedSurface3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.OriginalBoundaryCorrectedSurface3D", fields: 2, using: &admission)
        try encoder.field("boundaries", boundaries, using: &admission)
        try encoder.field("construction", construction, using: &admission)
    }
}
