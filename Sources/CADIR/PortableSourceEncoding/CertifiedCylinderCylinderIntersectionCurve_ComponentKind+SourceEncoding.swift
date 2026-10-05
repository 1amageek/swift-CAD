import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedCylinderCylinderIntersectionCurve.ComponentKind`.
extension CADGeometry.CertifiedCylinderCylinderIntersectionCurve.ComponentKind: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADGeometry.CertifiedCylinderCylinderIntersectionCurve.ComponentKind", caseName: rawValue, values: 0)
    }
}
