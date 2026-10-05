import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FaceUnwrapFeature`.
extension CADIR.FaceUnwrapFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.FaceUnwrapFeature", fields: 2)
        try encoder.field("face", face)
        try encoder.field("target", target)
    }
}
