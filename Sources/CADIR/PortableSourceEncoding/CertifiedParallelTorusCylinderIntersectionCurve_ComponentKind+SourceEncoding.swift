import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedParallelTorusCylinderIntersectionCurve.ComponentKind`.
extension CADGeometry.CertifiedParallelTorusCylinderIntersectionCurve.ComponentKind: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADGeometry.CertifiedParallelTorusCylinderIntersectionCurve.ComponentKind", caseName: rawValue, values: 0)
    }
}
