import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADTopology.Edge`.
extension CADTopology.Edge: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADTopology.Edge", fields: 5, using: &admission)
        try encoder.field("curveID", curveID, using: &admission)
        try encoder.field("endVertexID", endVertexID, using: &admission)
        try encoder.field("id", id, using: &admission)
        try encoder.field("startVertexID", startVertexID, using: &admission)
        try encoder.field("trim", trim, using: &admission)
    }
}
