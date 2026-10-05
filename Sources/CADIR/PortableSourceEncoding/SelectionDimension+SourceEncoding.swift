import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SelectionDimension`.
extension CADIR.SelectionDimension: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SelectionDimension", fields: 6)
        try encoder.field("first", first)
        try encoder.field("id", id)
        try encoder.field("kind", kind)
        try encoder.field("name", name)
        try encoder.field("second", second)
        try encoder.field("target", target)
    }
}
