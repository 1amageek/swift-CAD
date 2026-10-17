import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedAnalyticBSplineIntersectionCurve`.
extension CADGeometry.CertifiedAnalyticBSplineIntersectionCurve: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.CertifiedAnalyticBSplineIntersectionCurve", fields: 5, using: &admission)
        try encoder.field("analyticIsFirst", analyticIsFirst, using: &admission)
        try encoder.field("analyticSurface", analyticSurface, using: &admission)
        try encoder.field("boundedSurface", boundedSurface, using: &admission)
        try encoder.field("implicitCurve", implicitCurve, using: &admission)
        try encoder.field("periodicSeamOffset", periodicSeamOffset, using: &admission)
    }
}
