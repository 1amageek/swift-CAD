import CADCore

/// Encodes original source fields owned by `CADGeometry.CertifiedCylinderCylinderIntersectionCurve`.
extension CADGeometry.CertifiedCylinderCylinderIntersectionCurve: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.CertifiedCylinderCylinderIntersectionCurve", fields: 7)
        try encoder.field("certificationTolerance", certificationTolerance)
        try encoder.field("componentKind", componentKind)
        try encoder.field("lowerAngle", lowerAngle)
        try encoder.field("maximumResidualUpperBound", maximumResidualUpperBound)
        try encoder.field("parameterizedSurface", parameterizedSurface)
        try encoder.field("referenceSurface", referenceSurface)
        try encoder.field("upperAngle", upperAngle)
    }
}
