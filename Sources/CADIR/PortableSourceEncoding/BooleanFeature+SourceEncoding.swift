import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.BooleanFeature`.
extension CADIR.BooleanFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.BooleanFeature", fields: 6, using: &admission)
        try encoder.field("keepTools", keepTools, using: &admission)
        try encoder.field("operation", operation, using: &admission)
        try encoder.field("targetMaterial", targetMaterial, using: &admission)
        try encoder.field("targets", targets, using: &admission)
        try encoder.field("toolMaterial", toolMaterial, using: &admission)
        try encoder.field("tools", tools, using: &admission)
    }
}
