import CADCore

/// Encodes original source fields owned by `CADGeometry.CertifiedGeneralTorusTorusIntersectionCurve`.
extension CADGeometry.CertifiedGeneralTorusTorusIntersectionCurve: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.CertifiedGeneralTorusTorusIntersectionCurve", fields: 9)
        try encoder.field("certificationTolerance", certificationTolerance)
        try encoder.field("componentCount", componentCount)
        try encoder.field("componentIndex", componentIndex)
        try encoder.field("maximumIterations", maximumIterations)
        try encoder.field("maximumResidualUpperBound", maximumResidualUpperBound)
        try encoder.field("maximumSeedCount", maximumSeedCount)
        try encoder.field("maximumSubdivisionDepth", maximumSubdivisionDepth)
        try encoder.field("parameterizedSurface", parameterizedSurface)
        try encoder.field("referenceSurface", referenceSurface)
    }
}
