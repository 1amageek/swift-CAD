import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.SurfaceLiftCurve3D`.
extension CADGeometry.SurfaceLiftCurve3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.SurfaceLiftCurve3D", fields: 2)
        try encoder.field("parameterCurve", parameterCurve)
        try encoder.field("surface", surface)
    }
}
