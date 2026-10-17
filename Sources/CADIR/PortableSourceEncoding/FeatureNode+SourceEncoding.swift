import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FeatureNode`.
extension CADIR.FeatureNode: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.FeatureNode", fields: 6, using: &admission)
        try encoder.field("id", id, using: &admission)
        try encoder.field("inputs", inputs, using: &admission)
        try encoder.field("isSuppressed", isSuppressed, using: &admission)
        try encoder.field("name", name, using: &admission)
        try encoder.field("operation", operation, using: &admission)
        try encoder.field("outputs", outputs, using: &admission)
    }
}
