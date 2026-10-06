import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedParallelTorusTorusIntersectionCurve.ComponentKind`.
extension CADGeometry.CertifiedParallelTorusTorusIntersectionCurve.ComponentKind: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADGeometry.CertifiedParallelTorusTorusIntersectionCurve.ComponentKind", caseName: rawValue, values: 0)
    }
}
