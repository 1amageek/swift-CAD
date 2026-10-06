import CADCore
import CADGeometry

/// Encodes the complete authored final support source, excluding preparation caches.
extension CADGeometry.OriginalBoundaryCorrectedSurface3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.OriginalBoundaryCorrectedSurface3D", fields: 2)
        try encoder.field("boundaries", boundaries)
        try encoder.field("construction", construction)
    }
}
