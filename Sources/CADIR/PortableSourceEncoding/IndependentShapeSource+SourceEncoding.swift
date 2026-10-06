import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeSource`.
extension CADIR.IndependentShapeSource: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.IndependentShapeSource", fields: 23)
        try encoder.field("ambientContexts", ambientContexts)
        try encoder.field("ambientOriginalAngularSource", ambientOriginalAngularSource)
        try encoder.field("ambientOriginalLengthSource", ambientOriginalLengthSource)
        try encoder.field("contexts", contexts)
        try encoder.field("curveLinearSources", curveLinearSources)
        try encoder.field("curveNames", curveNames)
        try encoder.field("curvePositionFrames", curvePositionFrames)
        try encoder.field("curveSplineSources", curveSplineSources)
        try encoder.field("definitions", definitions)
        try encoder.field("frames", frames)
        try encoder.field("geometricSets", geometricSets)
        try encoder.field("geometry", geometry)
        try encoder.field("groups", groups)
        try encoder.field("instances", instances)
        try encoder.field("items", items)
        try encoder.field("originalSTEPGroups", originalSTEPGroups)
        try encoder.field("productAssociations", productAssociations)
        try encoder.field("representations", representations)
        try encoder.field("roots", roots)
        try encoder.field("surfaceAngularMeasures", surfaceAngularMeasures)
        try encoder.field("surfaceNames", surfaceNames)
        try encoder.field("surfacePositionFrames", surfacePositionFrames)
        try encoder.field("surfaceSplineSources", surfaceSplineSources)
    }
}
