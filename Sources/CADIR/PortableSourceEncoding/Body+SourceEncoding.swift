import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADTopology.Body`.
extension CADTopology.Body: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADTopology.Body", fields: 4, using: &admission)
        try encoder.field("id", id, using: &admission)
        try encoder.field("material", material, using: &admission)
        try encoder.field("name", name, using: &admission)
        try encoder.field("topology", topology, using: &admission)
    }
}
