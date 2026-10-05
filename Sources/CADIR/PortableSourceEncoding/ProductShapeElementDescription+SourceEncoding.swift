import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductShapeElementDescription`.
extension CADIR.ProductShapeElementDescription: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ProductShapeElementDescription", fields: 2)
        try encoder.field("description", description)
        try encoder.field("target", target)
    }
}
