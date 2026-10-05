import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FilletFeature`.
extension CADIR.FilletFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.FilletFeature", fields: 11)
        try encoder.field("allEdges", allEdges)
        try encoder.field("edges", edges)
        try encoder.field("endRadius", endRadius)
        try encoder.field("limits", limits)
        try encoder.field("radius", radius)
        try encoder.field("shape", shape)
        try encoder.field("tangentEdges", tangentEdges)
        try encoder.field("target", target)
        try encoder.field("tension", tension)
        try encoder.field("variablePoints", variablePoints)
        try encoder.field("yBlend", yBlend)
    }
}
