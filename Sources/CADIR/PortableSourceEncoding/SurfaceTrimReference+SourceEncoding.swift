import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceTrimReference`.
extension CADIR.SurfaceTrimReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SurfaceTrimReference", fields: 3)
        try encoder.field("edgeIndex", edgeIndex)
        try encoder.field("loopIndex", loopIndex)
        try encoder.field("surface", surface)
    }
}
