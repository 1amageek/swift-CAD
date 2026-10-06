import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceKnotReference`.
extension CADIR.SurfaceKnotReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SurfaceKnotReference", fields: 3)
        try encoder.field("direction", direction)
        try encoder.field("knotIndex", knotIndex)
        try encoder.field("surface", surface)
    }
}
