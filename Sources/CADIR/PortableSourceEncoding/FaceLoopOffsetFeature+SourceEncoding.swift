import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FaceLoopOffsetFeature`.
extension CADIR.FaceLoopOffsetFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.FaceLoopOffsetFeature", fields: 6, using: &admission)
        try encoder.field("distance", distance, using: &admission)
        try encoder.field("faces", faces, using: &admission)
        try encoder.field("gapFill", gapFill, using: &admission)
        try encoder.field("isIndividual", isIndividual, using: &admission)
        try encoder.field("side", side, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}
