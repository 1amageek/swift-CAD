import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FaceOffsetFeature`.
extension CADIR.FaceOffsetFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.FaceOffsetFeature", fields: 5, using: &admission)
        try encoder.field("adjacentAngle", adjacentAngle, using: &admission)
        try encoder.field("distance", distance, using: &admission)
        try encoder.field("faces", faces, using: &admission)
        try encoder.field("grow", grow, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}
