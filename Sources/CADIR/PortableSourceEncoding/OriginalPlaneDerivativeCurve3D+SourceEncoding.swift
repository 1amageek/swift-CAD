import CADCore
import CADGeometry

/// Encodes the complete original plane derivative source, excluding derived caches.
extension CADGeometry.OriginalPlaneDerivativeCurve3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.OriginalPlaneDerivativeCurve3D", fields: 3)
        try encoder.field("endConstraints", endConstraints)
        try encoder.field("source", source)
        try encoder.field("startConstraints", startConstraints)
    }
}
