import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedSphereConeIntersectionCurve.ComponentKind`.
extension CADGeometry.CertifiedSphereConeIntersectionCurve.ComponentKind: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADGeometry.CertifiedSphereConeIntersectionCurve.ComponentKind", caseName: rawValue, values: 0, using: &admission)
    }
}
