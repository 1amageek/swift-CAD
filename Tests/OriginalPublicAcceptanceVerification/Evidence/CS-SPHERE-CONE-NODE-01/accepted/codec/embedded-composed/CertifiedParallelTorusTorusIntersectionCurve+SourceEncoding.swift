import CADCore

/// Encodes original source fields owned by `CADGeometry.CertifiedParallelTorusTorusIntersectionCurve`.
extension CADGeometry.CertifiedParallelTorusTorusIntersectionCurve: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.CertifiedParallelTorusTorusIntersectionCurve", fields: 9)
        try encoder.field("branchCount", branchCount)
        try encoder.field("branchIndex", branchIndex)
        try encoder.field("certificationTolerance", certificationTolerance)
        try encoder.field("componentKind", componentKind)
        try encoder.field("maximumCellCount", maximumCellCount)
        try encoder.field("maximumResidualUpperBound", maximumResidualUpperBound)
        try encoder.field("maximumSubdivisionDepth", maximumSubdivisionDepth)
        try encoder.field("primarySurface", primarySurface)
        try encoder.field("secondarySurface", secondarySurface)
    }
}
