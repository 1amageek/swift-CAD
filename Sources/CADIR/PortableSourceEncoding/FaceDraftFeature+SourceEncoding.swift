import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FaceDraftFeature`.
extension CADIR.FaceDraftFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.FaceDraftFeature", fields: 6)
        try encoder.field("angle", angle)
        try encoder.field("faces", faces)
        try encoder.field("grow", grow)
        try encoder.field("neutralFace", neutralFace)
        try encoder.field("neutralOffset", neutralOffset)
        try encoder.field("target", target)
    }
}
