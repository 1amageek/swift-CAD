import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.LinearPatternFeature`.
extension CADIR.LinearPatternFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.LinearPatternFeature", fields: 4, using: &admission)
        try encoder.field("count", count, using: &admission)
        try encoder.field("direction", direction, using: &admission)
        try encoder.field("spacing", spacing, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}
