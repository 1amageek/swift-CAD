import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeItem`.
extension CADIR.IndependentShapeItem: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.IndependentShapeItem", fields: 5)
        try encoder.field("geometry", geometry)
        try encoder.field("id", id)
        try encoder.field("name", name)
        try encoder.field("traversalSource", traversalSource)
        try encoder.field("trimmingSource", trimmingSource)
    }
}
