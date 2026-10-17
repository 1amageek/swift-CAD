import CADCore

/// Retains original shared native [v][u] controls and every authored surface assertion.
extension OriginalSTEPSplineSurfaceSource: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.OriginalSTEPSplineSurfaceSource", fields: 7, using: &admission)
        try encoder.field("controlPointRows", controlPointRows, using: &admission)
        try encoder.field("isRational", isRational, using: &admission)
        try encoder.field("knotSpecification", knotSpecification, using: &admission)
        try encoder.field("selfIntersect", selfIntersect, using: &admission)
        try encoder.field("surfaceForm", surfaceForm, using: &admission)
        try encoder.field("uClosed", uClosed, using: &admission)
        try encoder.field("vClosed", vClosed, using: &admission)
    }
}
