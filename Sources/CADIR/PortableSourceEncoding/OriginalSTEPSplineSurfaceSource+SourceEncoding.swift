import CADCore

/// Retains original shared native [v][u] controls and every authored surface assertion.
extension OriginalSTEPSplineSurfaceSource: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.OriginalSTEPSplineSurfaceSource", fields: 7)
        try encoder.field("controlPointRows", controlPointRows)
        try encoder.field("isRational", isRational)
        try encoder.field("knotSpecification", knotSpecification)
        try encoder.field("selfIntersect", selfIntersect)
        try encoder.field("surfaceForm", surfaceForm)
        try encoder.field("uClosed", uClosed)
        try encoder.field("vClosed", vClosed)
    }
}
