import CADCore

/// Encodes original source fields owned by `CADGeometry.CertifiedSphereTorusIntersectionCurve`.
extension CADGeometry.CertifiedSphereTorusIntersectionCurve: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.CertifiedSphereTorusIntersectionCurve", fields: 7)
        try encoder.field("certificationTolerance", certificationTolerance)
        try encoder.field("componentKind", componentKind)
        try encoder.field("lowerAngle", lowerAngle)
        try encoder.field("maximumResidualUpperBound", maximumResidualUpperBound)
        try encoder.field("sphereSurface", sphereSurface)
        try encoder.field("torusSurface", torusSurface)
        try encoder.field("upperAngle", upperAngle)
    }
}
