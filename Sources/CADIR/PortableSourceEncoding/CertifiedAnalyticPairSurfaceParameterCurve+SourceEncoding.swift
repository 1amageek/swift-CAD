import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedAnalyticPairSurfaceParameterCurve`.
extension CADGeometry.CertifiedAnalyticPairSurfaceParameterCurve: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.CertifiedAnalyticPairSurfaceParameterCurve", fields: 4)
        try encoder.field("endFraction", endFraction)
        try encoder.field("intersection", intersection)
        try encoder.field("role", role)
        try encoder.field("startFraction", startFraction)
    }
}
