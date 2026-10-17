import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedPlaneTorusIntersectionCurve.ComponentKind`.
extension CADGeometry.CertifiedPlaneTorusIntersectionCurve.ComponentKind: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADGeometry.CertifiedPlaneTorusIntersectionCurve.ComponentKind", caseName: rawValue, values: 0, using: &admission)
    }
}
