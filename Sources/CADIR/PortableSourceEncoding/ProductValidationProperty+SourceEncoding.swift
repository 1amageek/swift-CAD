import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductValidationProperty`.
extension CADIR.ProductValidationProperty: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ProductValidationProperty", fields: 5)
        try encoder.field("description", description)
        try encoder.field("id", id)
        try encoder.field("name", name)
        try encoder.field("target", target)
        try encoder.field("value", value)
    }
}
