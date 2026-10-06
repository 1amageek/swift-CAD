import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.BooleanFeature`.
extension CADIR.BooleanFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.BooleanFeature", fields: 6)
        try encoder.field("keepTools", keepTools)
        try encoder.field("operation", operation)
        try encoder.field("targetMaterial", targetMaterial)
        try encoder.field("targets", targets)
        try encoder.field("toolMaterial", toolMaterial)
        try encoder.field("tools", tools)
    }
}
