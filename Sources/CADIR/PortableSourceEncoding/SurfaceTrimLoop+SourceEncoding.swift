import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceTrimLoop`.
extension CADIR.SurfaceTrimLoop: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SurfaceTrimLoop", fields: 2, using: &admission)
        try encoder.field("parameterCurves", parameterCurves, using: &admission)
        try encoder.field("role", role, using: &admission)
    }
}
