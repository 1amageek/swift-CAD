import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.GridPatternFeature`.
extension CADIR.GridPatternFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.GridPatternFeature", fields: 7)
        try encoder.field("firstCount", firstCount)
        try encoder.field("firstDirection", firstDirection)
        try encoder.field("firstSpacing", firstSpacing)
        try encoder.field("secondCount", secondCount)
        try encoder.field("secondDirection", secondDirection)
        try encoder.field("secondSpacing", secondSpacing)
        try encoder.field("target", target)
    }
}
