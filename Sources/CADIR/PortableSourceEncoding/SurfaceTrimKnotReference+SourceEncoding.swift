import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceTrimKnotReference`.
extension CADIR.SurfaceTrimKnotReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SurfaceTrimKnotReference", fields: 2)
        try encoder.field("knotIndex", knotIndex)
        try encoder.field("trim", trim)
    }
}
