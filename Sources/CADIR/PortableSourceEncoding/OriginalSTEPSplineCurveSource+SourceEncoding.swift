import CADCore

/// Retains original shared controls and all authored standard spline assertions.
extension OriginalSTEPSplineCurveSource: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.OriginalSTEPSplineCurveSource", fields: 6, using: &admission)
        try encoder.field("closed", closed, using: &admission)
        try encoder.field("controlPoints", controlPoints, using: &admission)
        try encoder.field("curveForm", curveForm, using: &admission)
        try encoder.field("isRational", isRational, using: &admission)
        try encoder.field("knotSpecification", knotSpecification, using: &admission)
        try encoder.field("selfIntersect", selfIntersect, using: &admission)
    }
}
