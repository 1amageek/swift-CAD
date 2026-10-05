import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FaceDeleteFeature`.
extension CADIR.FaceDeleteFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.FaceDeleteFeature", fields: 3)
        try encoder.field("faces", faces)
        try encoder.field("heals", heals)
        try encoder.field("target", target)
    }
}
