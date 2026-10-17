import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeItem`.
extension CADIR.IndependentShapeItem: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.IndependentShapeItem", fields: 5, using: &admission)
        try encoder.field("geometry", geometry, using: &admission)
        try encoder.field("id", id, using: &admission)
        try encoder.field("name", name, using: &admission)
        try encoder.field("traversalSource", traversalSource, using: &admission)
        try encoder.field("trimmingSource", trimmingSource, using: &admission)
    }
}
