import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve`.
extension CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve", fields: 3, using: &admission)
        try encoder.field("definition", definition, using: &admission)
        try encoder.field("firstSurface", firstSurface, using: &admission)
        try encoder.field("secondSurface", secondSurface, using: &admission)
    }
}
