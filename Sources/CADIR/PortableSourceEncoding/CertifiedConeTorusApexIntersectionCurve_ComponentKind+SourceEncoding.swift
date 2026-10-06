import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedConeTorusApexIntersectionCurve.ComponentKind`.
extension CADGeometry.CertifiedConeTorusApexIntersectionCurve.ComponentKind: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADGeometry.CertifiedConeTorusApexIntersectionCurve.ComponentKind", caseName: rawValue, values: 0)
    }
}
