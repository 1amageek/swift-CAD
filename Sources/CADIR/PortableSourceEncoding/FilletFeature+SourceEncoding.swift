import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FilletFeature`.
extension CADIR.FilletFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.FilletFeature", fields: 11, using: &admission)
        try encoder.field("allEdges", allEdges, using: &admission)
        try encoder.field("edges", edges, using: &admission)
        try encoder.field("endRadius", endRadius, using: &admission)
        try encoder.field("limits", limits, using: &admission)
        try encoder.field("radius", radius, using: &admission)
        try encoder.field("shape", shape, using: &admission)
        try encoder.field("tangentEdges", tangentEdges, using: &admission)
        try encoder.field("target", target, using: &admission)
        try encoder.field("tension", tension, using: &admission)
        try encoder.field("variablePoints", variablePoints, using: &admission)
        try encoder.field("yBlend", yBlend, using: &admission)
    }
}
