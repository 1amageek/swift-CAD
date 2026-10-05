import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.XNurbsFeature`.
extension CADIR.XNurbsFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.XNurbsFeature", fields: 9)
        try encoder.field("angleTolerance", angleTolerance)
        try encoder.field("boundaries", boundaries)
        try encoder.field("boundaryFlow", boundaryFlow)
        try encoder.field("flatness", flatness)
        try encoder.field("guides", guides)
        try encoder.field("positionTolerance", positionTolerance)
        try encoder.field("quadSided", quadSided)
        try encoder.field("quality", quality)
        try encoder.field("satisfiesTolerances", satisfiesTolerances)
    }
}
