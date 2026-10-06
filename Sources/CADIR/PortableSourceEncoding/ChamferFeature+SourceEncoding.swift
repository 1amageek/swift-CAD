import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ChamferFeature`.
extension CADIR.ChamferFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ChamferFeature", fields: 8)
        try encoder.field("angle", angle)
        try encoder.field("distance", distance)
        try encoder.field("edges", edges)
        try encoder.field("flipped", flipped)
        try encoder.field("limits", limits)
        try encoder.field("mode", mode)
        try encoder.field("tangentEdges", tangentEdges)
        try encoder.field("target", target)
    }
}
