import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductLayer`.
extension CADIR.ProductLayer: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.ProductLayer", fields: 4, using: &admission)
        try encoder.field("description", description, using: &admission)
        try encoder.field("id", id, using: &admission)
        let orderedMembers = try encoder.canonicalOrder(members, using: &admission)
        try encoder.field("members", orderedMembers, using: &admission)
        try encoder.field("name", name, using: &admission)
    }
}
