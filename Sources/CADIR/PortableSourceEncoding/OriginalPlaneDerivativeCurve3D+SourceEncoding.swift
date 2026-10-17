import CADCore
import CADGeometry

/// Encodes the complete original plane derivative source, excluding derived caches.
extension CADGeometry.OriginalPlaneDerivativeCurve3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.OriginalPlaneDerivativeCurve3D", fields: 3, using: &admission)
        try encoder.field("endConstraints", endConstraints, using: &admission)
        try encoder.field("source", source, using: &admission)
        try encoder.field("startConstraints", startConstraints, using: &admission)
    }
}
