import CADCore

/// Encodes original source fields owned by `CADGeometry.CertifiedAnalyticBSplineIntersectionCurve`.
extension CADGeometry.CertifiedAnalyticBSplineIntersectionCurve: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.CertifiedAnalyticBSplineIntersectionCurve", fields: 5)
        try encoder.field("analyticIsFirst", analyticIsFirst)
        try encoder.field("analyticSurface", analyticSurface)
        try encoder.field("boundedSurface", boundedSurface)
        try encoder.field("implicitCurve", implicitCurve)
        try encoder.field("periodicSeamOffset", periodicSeamOffset)
    }
}
