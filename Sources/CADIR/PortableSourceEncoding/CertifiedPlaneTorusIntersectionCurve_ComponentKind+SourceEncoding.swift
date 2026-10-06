import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedPlaneTorusIntersectionCurve.ComponentKind`.
extension CADGeometry.CertifiedPlaneTorusIntersectionCurve.ComponentKind: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADGeometry.CertifiedPlaneTorusIntersectionCurve.ComponentKind", caseName: rawValue, values: 0)
    }
}
