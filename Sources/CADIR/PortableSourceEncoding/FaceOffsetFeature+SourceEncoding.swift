import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FaceOffsetFeature`.
extension CADIR.FaceOffsetFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.FaceOffsetFeature", fields: 5)
        try encoder.field("adjacentAngle", adjacentAngle)
        try encoder.field("distance", distance)
        try encoder.field("faces", faces)
        try encoder.field("grow", grow)
        try encoder.field("target", target)
    }
}
