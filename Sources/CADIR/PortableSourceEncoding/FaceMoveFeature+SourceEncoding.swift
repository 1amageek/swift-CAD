import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FaceMoveFeature`.
extension CADIR.FaceMoveFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.FaceMoveFeature", fields: 3)
        try encoder.field("face", face)
        try encoder.field("target", target)
        try encoder.field("translation", translation)
    }
}
