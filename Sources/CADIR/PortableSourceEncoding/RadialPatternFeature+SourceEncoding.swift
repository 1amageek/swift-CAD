import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.RadialPatternFeature`.
extension CADIR.RadialPatternFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.RadialPatternFeature", fields: 5)
        try encoder.field("angularSpacing", angularSpacing)
        try encoder.field("axisDirection", axisDirection)
        try encoder.field("axisOrigin", axisOrigin)
        try encoder.field("count", count)
        try encoder.field("target", target)
    }
}
