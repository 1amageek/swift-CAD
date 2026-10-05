import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FaceLoopOffsetFeature`.
extension CADIR.FaceLoopOffsetFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.FaceLoopOffsetFeature", fields: 6)
        try encoder.field("distance", distance)
        try encoder.field("faces", faces)
        try encoder.field("gapFill", gapFill)
        try encoder.field("isIndividual", isIndividual)
        try encoder.field("side", side)
        try encoder.field("target", target)
    }
}
