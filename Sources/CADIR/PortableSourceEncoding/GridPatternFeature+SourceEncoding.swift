import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.GridPatternFeature`.
extension CADIR.GridPatternFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.GridPatternFeature", fields: 7, using: &admission)
        try encoder.field("firstCount", firstCount, using: &admission)
        try encoder.field("firstDirection", firstDirection, using: &admission)
        try encoder.field("firstSpacing", firstSpacing, using: &admission)
        try encoder.field("secondCount", secondCount, using: &admission)
        try encoder.field("secondDirection", secondDirection, using: &admission)
        try encoder.field("secondSpacing", secondSpacing, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}
