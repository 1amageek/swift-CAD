import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.UntrimFaceFeature`.
extension CADIR.UntrimFaceFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.UntrimFaceFeature", fields: 3)
        try encoder.field("face", face)
        try encoder.field("keepsEdges", keepsEdges)
        try encoder.field("target", target)
    }
}
