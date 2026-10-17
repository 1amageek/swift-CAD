import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FaceMatchFeature`.
extension CADIR.FaceMatchFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.FaceMatchFeature", fields: 7, using: &admission)
        try encoder.field("faces", faces, using: &admission)
        try encoder.field("front", front, using: &admission)
        try encoder.field("grow", grow, using: &admission)
        try encoder.field("referenceFace", referenceFace, using: &admission)
        try encoder.field("source", source, using: &admission)
        try encoder.field("sourcePlacement", sourcePlacement, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}
