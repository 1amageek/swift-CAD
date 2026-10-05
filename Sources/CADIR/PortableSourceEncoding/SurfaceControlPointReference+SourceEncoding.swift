import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceControlPointReference`.
extension CADIR.SurfaceControlPointReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SurfaceControlPointReference", fields: 3)
        try encoder.field("surface", surface)
        try encoder.field("uIndex", uIndex)
        try encoder.field("vIndex", vIndex)
    }
}
