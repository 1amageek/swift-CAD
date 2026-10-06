import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FaceKnifeFeature`.
extension CADIR.FaceKnifeFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.FaceKnifeFeature", fields: 3)
        try encoder.field("face", face)
        try encoder.field("loop", loop)
        try encoder.field("target", target)
    }
}
