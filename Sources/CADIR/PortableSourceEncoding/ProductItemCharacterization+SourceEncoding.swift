import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductItemCharacterization`.
extension CADIR.ProductItemCharacterization: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ProductItemCharacterization", fields: 3)
        try encoder.field("description", description)
        try encoder.field("name", name)
        try encoder.field("target", target)
    }
}
