import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.SurfaceLiftCurve3D`.
extension CADGeometry.SurfaceLiftCurve3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.SurfaceLiftCurve3D", fields: 2, using: &admission)
        try encoder.field("parameterCurve", parameterCurve, using: &admission)
        try encoder.field("surface", surface, using: &admission)
    }
}
