import CADCore

/// Retains original shared controls and all authored standard spline assertions.
extension OriginalSTEPSplineCurveSource: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.OriginalSTEPSplineCurveSource", fields: 6)
        try encoder.field("closed", closed)
        try encoder.field("controlPoints", controlPoints)
        try encoder.field("curveForm", curveForm)
        try encoder.field("isRational", isRational)
        try encoder.field("knotSpecification", knotSpecification)
        try encoder.field("selfIntersect", selfIntersect)
    }
}
