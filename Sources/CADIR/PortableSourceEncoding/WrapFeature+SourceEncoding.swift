import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.WrapFeature`.
extension CADIR.WrapFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.WrapFeature", fields: 7)
        try encoder.field("keepsTarget", keepsTarget)
        try encoder.field("options", options)
        try encoder.field("referenceFace", referenceFace)
        try encoder.field("referencePlacement", referencePlacement)
        try encoder.field("target", target)
        try encoder.field("targetFace", targetFace)
        try encoder.field("targetPlacement", targetPlacement)
    }
}
