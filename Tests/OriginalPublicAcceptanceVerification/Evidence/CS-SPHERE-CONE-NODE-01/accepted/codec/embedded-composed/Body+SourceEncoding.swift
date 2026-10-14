import CADCore
import CADTopology

/// Encodes original source fields owned by `CADTopology.Body`.
extension CADTopology.Body: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADTopology.Body", fields: 4)
        try encoder.field("id", id)
        try encoder.field("material", material)
        try encoder.field("name", name)
        try encoder.field("topology", topology)
    }
}
