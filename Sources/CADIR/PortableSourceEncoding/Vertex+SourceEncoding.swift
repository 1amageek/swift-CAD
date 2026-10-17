import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADTopology.Vertex`.
extension CADTopology.Vertex: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADTopology.Vertex", fields: 2, using: &admission)
        try encoder.field("id", id, using: &admission)
        try encoder.field("point", point, using: &admission)
    }
}
