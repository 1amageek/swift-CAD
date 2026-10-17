import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedBoundedPlaneConeIntersectionCurve`.
extension CADGeometry.CertifiedBoundedPlaneConeIntersectionCurve: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.CertifiedBoundedPlaneConeIntersectionCurve", fields: 7, using: &admission)
        try encoder.field("analyticCurve", analyticCurve, using: &admission)
        try encoder.field("certificationTolerance", certificationTolerance, using: &admission)
        try encoder.field("coneSurface", coneSurface, using: &admission)
        try encoder.field("endParameter", endParameter, using: &admission)
        try encoder.field("maximumResidualUpperBound", maximumResidualUpperBound, using: &admission)
        try encoder.field("planeSurface", planeSurface, using: &admission)
        try encoder.field("startParameter", startParameter, using: &admission)
    }
}
