import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductAttributeTarget`.
extension CADIR.ProductAttributeTarget: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.ProductAttributeTarget", fields: 5, using: &admission)
        try encoder.field("definitionID", definitionID, using: &admission)
        try encoder.field("geometry", geometry, using: &admission)
        try encoder.field("kind", kind, using: &admission)
        try encoder.field("path", path, using: &admission)
        try encoder.field("usageID", usageID, using: &admission)
    }
}
