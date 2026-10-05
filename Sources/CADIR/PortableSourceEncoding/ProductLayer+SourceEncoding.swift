import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductLayer`.
extension CADIR.ProductLayer: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ProductLayer", fields: 4)
        try encoder.field("description", description)
        try encoder.field("id", id)
        let orderedMembers = try encoder.canonicalOrder(members)
        try encoder.field("members", orderedMembers)
        try encoder.field("name", name)
    }
}
