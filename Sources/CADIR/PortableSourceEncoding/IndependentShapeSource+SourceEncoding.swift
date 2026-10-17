import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeSource`.
extension CADIR.IndependentShapeSource: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.IndependentShapeSource", fields: 23, using: &admission)
        try encoder.field("ambientContexts", ambientContexts, using: &admission)
        try encoder.field("ambientOriginalAngularSource", ambientOriginalAngularSource, using: &admission)
        try encoder.field("ambientOriginalLengthSource", ambientOriginalLengthSource, using: &admission)
        try encoder.field("contexts", contexts, using: &admission)
        try encoder.field("curveLinearSources", curveLinearSources, using: &admission)
        try encoder.field("curveNames", curveNames, using: &admission)
        try encoder.field("curvePositionFrames", curvePositionFrames, using: &admission)
        try encoder.field("curveSplineSources", curveSplineSources, using: &admission)
        try encoder.field("definitions", definitions, using: &admission)
        try encoder.field("frames", frames, using: &admission)
        try encoder.field("geometricSets", geometricSets, using: &admission)
        try encoder.field("geometry", geometry, using: &admission)
        try encoder.field("groups", groups, using: &admission)
        try encoder.field("instances", instances, using: &admission)
        try encoder.field("items", items, using: &admission)
        try encoder.field("originalSTEPGroups", originalSTEPGroups, using: &admission)
        try encoder.field("productAssociations", productAssociations, using: &admission)
        try encoder.field("representations", representations, using: &admission)
        try encoder.field("roots", roots, using: &admission)
        try encoder.field("surfaceAngularMeasures", surfaceAngularMeasures, using: &admission)
        try encoder.field("surfaceNames", surfaceNames, using: &admission)
        try encoder.field("surfacePositionFrames", surfacePositionFrames, using: &admission)
        try encoder.field("surfaceSplineSources", surfaceSplineSources, using: &admission)
    }
}
