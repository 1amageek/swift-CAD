import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.ProjectedAnalyticSurfaceParameterCurve`.
extension CADGeometry.ProjectedAnalyticSurfaceParameterCurve: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.ProjectedAnalyticSurfaceParameterCurve", fields: 5, using: &admission)
        try encoder.field("certificationTolerance", certificationTolerance, using: &admission)
        try encoder.field("curve", curve, using: &admission)
        try encoder.field("endParameter", endParameter, using: &admission)
        try encoder.field("startParameter", startParameter, using: &admission)
        try encoder.field("surface", surface, using: &admission)
    }
}
