import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.DocumentAttribute`.
extension CADIR.DocumentAttribute: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.DocumentAttribute", fields: 4)
        try encoder.field("id", id)
        try encoder.field("name", name)
        try encoder.field("owner", owner)
        try encoder.field("value", value)
    }
}
