import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADCore.SchemaVersion`.
extension CADCore.SchemaVersion: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADCore.SchemaVersion", fields: 3)
        try encoder.field("major", major)
        try encoder.field("minor", minor)
        try encoder.field("patch", patch)
    }
}
