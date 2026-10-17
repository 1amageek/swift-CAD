import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveDrivenPatternFeature`.
extension CADIR.CurveDrivenPatternFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.CurveDrivenPatternFeature", fields: 5, using: &admission)
        try encoder.field("anchor", anchor, using: &admission)
        try encoder.field("count", count, using: &admission)
        try encoder.field("path", path, using: &admission)
        try encoder.field("referenceDirection", referenceDirection, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}
