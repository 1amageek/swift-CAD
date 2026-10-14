import CADCore

/// Encodes original source fields owned by `CADGeometry.ProjectedAnalyticSurfaceParameterCurve`.
extension CADGeometry.ProjectedAnalyticSurfaceParameterCurve: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.ProjectedAnalyticSurfaceParameterCurve", fields: 5)
        try encoder.field("certificationTolerance", certificationTolerance)
        try encoder.field("curve", curve)
        try encoder.field("endParameter", endParameter)
        try encoder.field("startParameter", startParameter)
        try encoder.field("surface", surface)
    }
}
