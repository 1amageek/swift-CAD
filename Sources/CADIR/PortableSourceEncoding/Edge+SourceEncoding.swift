import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADTopology.Edge`.
extension CADTopology.Edge: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADTopology.Edge", fields: 5)
        try encoder.field("curveID", curveID)
        try encoder.field("endVertexID", endVertexID)
        try encoder.field("id", id)
        try encoder.field("startVertexID", startVertexID)
        try encoder.field("trim", trim)
    }
}
