import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADCore.SchemaVersion`.
extension CADCore.SchemaVersion: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADCore.SchemaVersion", fields: 3, using: &admission)
        try encoder.field("major", major, using: &admission)
        try encoder.field("minor", minor, using: &admission)
        try encoder.field("patch", patch, using: &admission)
    }
}
