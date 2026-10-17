import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FaceUnwrapFeature`.
extension CADIR.FaceUnwrapFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.FaceUnwrapFeature", fields: 2, using: &admission)
        try encoder.field("face", face, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}
