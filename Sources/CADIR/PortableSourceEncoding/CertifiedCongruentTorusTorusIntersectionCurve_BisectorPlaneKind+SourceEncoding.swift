import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedCongruentTorusTorusIntersectionCurve.BisectorPlaneKind`.
extension CADGeometry.CertifiedCongruentTorusTorusIntersectionCurve.BisectorPlaneKind: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADGeometry.CertifiedCongruentTorusTorusIntersectionCurve.BisectorPlaneKind", caseName: rawValue, values: 0)
    }
}
