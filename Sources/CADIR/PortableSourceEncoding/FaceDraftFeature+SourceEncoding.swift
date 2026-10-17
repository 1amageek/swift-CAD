import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FaceDraftFeature`.
extension CADIR.FaceDraftFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.FaceDraftFeature", fields: 6, using: &admission)
        try encoder.field("angle", angle, using: &admission)
        try encoder.field("faces", faces, using: &admission)
        try encoder.field("grow", grow, using: &admission)
        try encoder.field("neutralFace", neutralFace, using: &admission)
        try encoder.field("neutralOffset", neutralOffset, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}
