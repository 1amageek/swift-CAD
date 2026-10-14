import CADCore

/// Encodes original source fields owned by `CADGeometry.CertifiedConeCylinderIntersectionCurve`.
extension CADGeometry.CertifiedConeCylinderIntersectionCurve: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.CertifiedConeCylinderIntersectionCurve", fields: 7)
        try encoder.field("certificationTolerance", certificationTolerance)
        try encoder.field("componentKind", componentKind)
        try encoder.field("coneSurface", coneSurface)
        try encoder.field("cylinderSurface", cylinderSurface)
        try encoder.field("lowerAngle", lowerAngle)
        try encoder.field("maximumResidualUpperBound", maximumResidualUpperBound)
        try encoder.field("upperAngle", upperAngle)
    }
}
