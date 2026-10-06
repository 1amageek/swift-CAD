import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedConeConeIntersectionCurve.ComponentKind`.
extension CADGeometry.CertifiedConeConeIntersectionCurve.ComponentKind: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADGeometry.CertifiedConeConeIntersectionCurve.ComponentKind", caseName: rawValue, values: 0)
    }
}
