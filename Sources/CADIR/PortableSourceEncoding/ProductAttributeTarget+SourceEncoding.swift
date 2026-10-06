import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductAttributeTarget`.
extension CADIR.ProductAttributeTarget: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ProductAttributeTarget", fields: 5)
        try encoder.field("definitionID", definitionID)
        try encoder.field("geometry", geometry)
        try encoder.field("kind", kind)
        try encoder.field("path", path)
        try encoder.field("usageID", usageID)
    }
}
