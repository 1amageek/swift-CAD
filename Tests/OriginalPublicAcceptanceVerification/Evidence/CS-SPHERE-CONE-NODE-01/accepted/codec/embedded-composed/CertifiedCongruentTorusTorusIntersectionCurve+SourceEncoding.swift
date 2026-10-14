import CADCore

/// Encodes original source fields owned by `CADGeometry.CertifiedCongruentTorusTorusIntersectionCurve`.
extension CADGeometry.CertifiedCongruentTorusTorusIntersectionCurve: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.CertifiedCongruentTorusTorusIntersectionCurve", fields: 8)
        try encoder.field("bisectorPlaneKind", bisectorPlaneKind)
        try encoder.field("branchCount", branchCount)
        try encoder.field("branchIndex", branchIndex)
        try encoder.field("certificationTolerance", certificationTolerance)
        try encoder.field("maximumResidualUpperBound", maximumResidualUpperBound)
        try encoder.field("primarySurface", primarySurface)
        try encoder.field("secondarySurface", secondarySurface)
        try encoder.field("sectionCurve", sectionCurve)
    }
}
