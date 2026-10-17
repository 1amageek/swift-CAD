import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveOffsetFeature`.
extension CADIR.CurveOffsetFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.CurveOffsetFeature", fields: 4, using: &admission)
        try encoder.field("distance", distance, using: &admission)
        try encoder.field("planeNormal", planeNormal, using: &admission)
        try encoder.field("side", side, using: &admission)
        try encoder.field("source", source, using: &admission)
    }
}
