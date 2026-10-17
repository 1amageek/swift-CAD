import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedConeTorusApexIntersectionCurve.ComponentKind`.
extension CADGeometry.CertifiedConeTorusApexIntersectionCurve.ComponentKind: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADGeometry.CertifiedConeTorusApexIntersectionCurve.ComponentKind", caseName: rawValue, values: 0, using: &admission)
    }
}
