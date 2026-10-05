import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceTrimLoop`.
extension CADIR.SurfaceTrimLoop: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SurfaceTrimLoop", fields: 2)
        try encoder.field("parameterCurves", parameterCurves)
        try encoder.field("role", role)
    }
}
