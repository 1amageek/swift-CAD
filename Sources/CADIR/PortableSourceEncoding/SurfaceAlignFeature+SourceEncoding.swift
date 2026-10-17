import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceAlignFeature`.
extension CADIR.SurfaceAlignFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SurfaceAlignFeature", fields: 14, using: &admission)
        try encoder.field("blendRows", blendRows, using: &admission)
        try encoder.field("boundaryFlow", boundaryFlow, using: &admission)
        try encoder.field("continuity", continuity, using: &admission)
        try encoder.field("inputShapeInfluence", inputShapeInfluence, using: &admission)
        try encoder.field("keepsOtherEdges", keepsOtherEdges, using: &admission)
        try encoder.field("layout", layout, using: &admission)
        try encoder.field("partialEnd", partialEnd, using: &admission)
        try encoder.field("partialStart", partialStart, using: &admission)
        try encoder.field("reference", reference, using: &admission)
        try encoder.field("referenceEdge", referenceEdge, using: &admission)
        try encoder.field("referencePlacement", referencePlacement, using: &admission)
        try encoder.field("target", target, using: &admission)
        try encoder.field("targetEdge", targetEdge, using: &admission)
        try encoder.field("tension", tension, using: &admission)
    }
}
