import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FaceKnifeFeature`.
extension CADIR.FaceKnifeFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.FaceKnifeFeature", fields: 3, using: &admission)
        try encoder.field("face", face, using: &admission)
        try encoder.field("loop", loop, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}
