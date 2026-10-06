import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductAttributeAssignment`.
extension CADIR.ProductAttributeAssignment: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ProductAttributeAssignment", fields: 4)
        try encoder.field("id", id)
        try encoder.field("overrides", overrides)
        try encoder.field("target", target)
        try encoder.field("value", value)
    }
}
