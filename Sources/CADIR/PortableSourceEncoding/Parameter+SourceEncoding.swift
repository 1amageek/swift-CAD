import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.Parameter`.
extension CADIR.Parameter: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.Parameter", fields: 4)
        try encoder.field("expression", expression)
        try encoder.field("id", id)
        try encoder.field("kind", kind)
        try encoder.field("name", name)
    }
}
