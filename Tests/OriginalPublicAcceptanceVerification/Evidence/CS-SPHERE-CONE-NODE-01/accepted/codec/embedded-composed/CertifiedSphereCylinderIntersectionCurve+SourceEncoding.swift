import CADCore

/// Encodes original source fields owned by `CADGeometry.CertifiedSphereCylinderIntersectionCurve`.
extension CADGeometry.CertifiedSphereCylinderIntersectionCurve: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.CertifiedSphereCylinderIntersectionCurve", fields: 7)
        try encoder.field("certificationTolerance", certificationTolerance)
        try encoder.field("componentKind", componentKind)
        try encoder.field("cylinderSurface", cylinderSurface)
        try encoder.field("lowerAngle", lowerAngle)
        try encoder.field("maximumResidualUpperBound", maximumResidualUpperBound)
        try encoder.field("sphereSurface", sphereSurface)
        try encoder.field("upperAngle", upperAngle)
    }
}
