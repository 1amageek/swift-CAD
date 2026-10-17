import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedAnalyticImplicitSurfaceParameterCurve`.
extension CADGeometry.CertifiedAnalyticImplicitSurfaceParameterCurve: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.CertifiedAnalyticImplicitSurfaceParameterCurve", fields: 3, using: &admission)
        try encoder.field("endFraction", endFraction, using: &admission)
        try encoder.field("intersection", intersection, using: &admission)
        try encoder.field("startFraction", startFraction, using: &admission)
    }
}
