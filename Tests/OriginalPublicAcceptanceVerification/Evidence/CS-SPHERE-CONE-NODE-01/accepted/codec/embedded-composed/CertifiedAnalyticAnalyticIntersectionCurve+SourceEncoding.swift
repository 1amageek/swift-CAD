import CADCore

/// Encodes original source fields owned by `CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve`.
extension CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve", fields: 3)
        try encoder.field("definition", definition)
        try encoder.field("firstSurface", firstSurface)
        try encoder.field("secondSurface", secondSurface)
    }
}
