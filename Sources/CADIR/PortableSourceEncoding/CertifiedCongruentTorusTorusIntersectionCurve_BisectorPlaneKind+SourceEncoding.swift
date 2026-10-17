import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedCongruentTorusTorusIntersectionCurve.BisectorPlaneKind`.
extension CADGeometry.CertifiedCongruentTorusTorusIntersectionCurve.BisectorPlaneKind: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADGeometry.CertifiedCongruentTorusTorusIntersectionCurve.BisectorPlaneKind", caseName: rawValue, values: 0, using: &admission)
    }
}
