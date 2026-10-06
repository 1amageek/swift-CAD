import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedAnalyticImplicitSurfaceParameterCurve`.
extension CADGeometry.CertifiedAnalyticImplicitSurfaceParameterCurve: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.CertifiedAnalyticImplicitSurfaceParameterCurve", fields: 3)
        try encoder.field("endFraction", endFraction)
        try encoder.field("intersection", intersection)
        try encoder.field("startFraction", startFraction)
    }
}
