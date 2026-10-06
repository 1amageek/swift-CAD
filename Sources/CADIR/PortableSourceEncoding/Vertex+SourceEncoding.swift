import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADTopology.Vertex`.
extension CADTopology.Vertex: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADTopology.Vertex", fields: 2)
        try encoder.field("id", id)
        try encoder.field("point", point)
    }
}
