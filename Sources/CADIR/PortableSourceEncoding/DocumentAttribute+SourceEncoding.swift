import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.DocumentAttribute`.
extension CADIR.DocumentAttribute: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.DocumentAttribute", fields: 4, using: &admission)
        try encoder.field("id", id, using: &admission)
        try encoder.field("name", name, using: &admission)
        try encoder.field("owner", owner, using: &admission)
        try encoder.field("value", value, using: &admission)
    }
}
