import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceReference`.
extension CADIR.SurfaceReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SurfaceReference", fields: 1)
        try encoder.field("subshape", subshape)
    }
}
