import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductAttributeAssignment`.
extension CADIR.ProductAttributeAssignment: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.ProductAttributeAssignment", fields: 4, using: &admission)
        try encoder.field("id", id, using: &admission)
        try encoder.field("overrides", overrides, using: &admission)
        try encoder.field("target", target, using: &admission)
        try encoder.field("value", value, using: &admission)
    }
}
