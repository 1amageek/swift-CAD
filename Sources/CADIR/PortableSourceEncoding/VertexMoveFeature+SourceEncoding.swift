import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.VertexMoveFeature`.
extension CADIR.VertexMoveFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.VertexMoveFeature", fields: 3)
        try encoder.field("target", target)
        try encoder.field("translation", translation)
        try encoder.field("vertex", vertex)
    }
}
