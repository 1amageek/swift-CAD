import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveDrivenPatternFeature`.
extension CADIR.CurveDrivenPatternFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.CurveDrivenPatternFeature", fields: 5)
        try encoder.field("anchor", anchor)
        try encoder.field("count", count)
        try encoder.field("path", path)
        try encoder.field("referenceDirection", referenceDirection)
        try encoder.field("target", target)
    }
}
