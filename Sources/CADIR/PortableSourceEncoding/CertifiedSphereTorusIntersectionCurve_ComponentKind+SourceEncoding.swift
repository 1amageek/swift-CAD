import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedSphereTorusIntersectionCurve.ComponentKind`.
extension CADGeometry.CertifiedSphereTorusIntersectionCurve.ComponentKind: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADGeometry.CertifiedSphereTorusIntersectionCurve.ComponentKind", caseName: rawValue, values: 0)
    }
}
