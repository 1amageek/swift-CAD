import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.RadialPatternFeature`.
extension CADIR.RadialPatternFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.RadialPatternFeature", fields: 5, using: &admission)
        try encoder.field("angularSpacing", angularSpacing, using: &admission)
        try encoder.field("axisDirection", axisDirection, using: &admission)
        try encoder.field("axisOrigin", axisOrigin, using: &admission)
        try encoder.field("count", count, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}
