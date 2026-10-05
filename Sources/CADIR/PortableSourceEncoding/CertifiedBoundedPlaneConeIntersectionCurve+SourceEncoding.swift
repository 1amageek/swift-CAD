import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedBoundedPlaneConeIntersectionCurve`.
extension CADGeometry.CertifiedBoundedPlaneConeIntersectionCurve: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.CertifiedBoundedPlaneConeIntersectionCurve", fields: 7)
        try encoder.field("analyticCurve", analyticCurve)
        try encoder.field("certificationTolerance", certificationTolerance)
        try encoder.field("coneSurface", coneSurface)
        try encoder.field("endParameter", endParameter)
        try encoder.field("maximumResidualUpperBound", maximumResidualUpperBound)
        try encoder.field("planeSurface", planeSurface)
        try encoder.field("startParameter", startParameter)
    }
}
