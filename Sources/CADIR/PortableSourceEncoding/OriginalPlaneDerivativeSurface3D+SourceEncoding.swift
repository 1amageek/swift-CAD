import CADCore
import CADGeometry

/// Encodes the complete original plane derivative source, excluding derived caches.
extension CADGeometry.OriginalPlaneDerivativeSurface3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.OriginalPlaneDerivativeSurface3D", fields: 4, using: &admission)
        try encoder.field("boundaries", boundaries, using: &admission)
        try encoder.field("construction", construction, using: &admission)
        try encoder.field("endConstraints", endConstraints, using: &admission)
        try encoder.field("startConstraints", startConstraints, using: &admission)
    }
}
