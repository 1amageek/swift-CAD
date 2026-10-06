import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.LinearPatternFeature`.
extension CADIR.LinearPatternFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.LinearPatternFeature", fields: 4)
        try encoder.field("count", count)
        try encoder.field("direction", direction)
        try encoder.field("spacing", spacing)
        try encoder.field("target", target)
    }
}
