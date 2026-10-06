import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceAlignFeature`.
extension CADIR.SurfaceAlignFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SurfaceAlignFeature", fields: 14)
        try encoder.field("blendRows", blendRows)
        try encoder.field("boundaryFlow", boundaryFlow)
        try encoder.field("continuity", continuity)
        try encoder.field("inputShapeInfluence", inputShapeInfluence)
        try encoder.field("keepsOtherEdges", keepsOtherEdges)
        try encoder.field("layout", layout)
        try encoder.field("partialEnd", partialEnd)
        try encoder.field("partialStart", partialStart)
        try encoder.field("reference", reference)
        try encoder.field("referenceEdge", referenceEdge)
        try encoder.field("referencePlacement", referencePlacement)
        try encoder.field("target", target)
        try encoder.field("targetEdge", targetEdge)
        try encoder.field("tension", tension)
    }
}
