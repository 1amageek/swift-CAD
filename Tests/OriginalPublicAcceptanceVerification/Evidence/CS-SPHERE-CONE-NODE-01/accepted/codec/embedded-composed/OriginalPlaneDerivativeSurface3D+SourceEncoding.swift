import CADCore

/// Encodes the complete original plane derivative source, excluding derived caches.
extension CADGeometry.OriginalPlaneDerivativeSurface3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.OriginalPlaneDerivativeSurface3D", fields: 4)
        try encoder.field("boundaries", boundaries)
        try encoder.field("construction", construction)
        try encoder.field("endConstraints", endConstraints)
        try encoder.field("startConstraints", startConstraints)
    }
}
