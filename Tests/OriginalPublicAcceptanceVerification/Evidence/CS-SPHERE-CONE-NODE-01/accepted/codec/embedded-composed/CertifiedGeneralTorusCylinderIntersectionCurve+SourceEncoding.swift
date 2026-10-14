import CADCore

/// Encodes original source fields owned by `CADGeometry.CertifiedGeneralTorusCylinderIntersectionCurve`.
extension CADGeometry.CertifiedGeneralTorusCylinderIntersectionCurve: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.CertifiedGeneralTorusCylinderIntersectionCurve", fields: 8)
        try encoder.field("branchCount", branchCount)
        try encoder.field("branchIndex", branchIndex)
        try encoder.field("certificationTolerance", certificationTolerance)
        try encoder.field("cylinderSurface", cylinderSurface)
        try encoder.field("maximumCellCount", maximumCellCount)
        try encoder.field("maximumResidualUpperBound", maximumResidualUpperBound)
        try encoder.field("maximumSubdivisionDepth", maximumSubdivisionDepth)
        try encoder.field("torusSurface", torusSurface)
    }
}
