import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FeatureNode`.
extension CADIR.FeatureNode: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.FeatureNode", fields: 6)
        try encoder.field("id", id)
        try encoder.field("inputs", inputs)
        try encoder.field("isSuppressed", isSuppressed)
        try encoder.field("name", name)
        try encoder.field("operation", operation)
        try encoder.field("outputs", outputs)
    }
}
