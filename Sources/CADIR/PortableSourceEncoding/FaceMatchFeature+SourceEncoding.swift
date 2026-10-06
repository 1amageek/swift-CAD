import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FaceMatchFeature`.
extension CADIR.FaceMatchFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.FaceMatchFeature", fields: 7)
        try encoder.field("faces", faces)
        try encoder.field("front", front)
        try encoder.field("grow", grow)
        try encoder.field("referenceFace", referenceFace)
        try encoder.field("source", source)
        try encoder.field("sourcePlacement", sourcePlacement)
        try encoder.field("target", target)
    }
}
