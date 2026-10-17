import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.WrapFeature`.
extension CADIR.WrapFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.WrapFeature", fields: 7, using: &admission)
        try encoder.field("keepsTarget", keepsTarget, using: &admission)
        try encoder.field("options", options, using: &admission)
        try encoder.field("referenceFace", referenceFace, using: &admission)
        try encoder.field("referencePlacement", referencePlacement, using: &admission)
        try encoder.field("target", target, using: &admission)
        try encoder.field("targetFace", targetFace, using: &admission)
        try encoder.field("targetPlacement", targetPlacement, using: &admission)
    }
}
