import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ChamferFeature`.
extension CADIR.ChamferFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.ChamferFeature", fields: 8, using: &admission)
        try encoder.field("angle", angle, using: &admission)
        try encoder.field("distance", distance, using: &admission)
        try encoder.field("edges", edges, using: &admission)
        try encoder.field("flipped", flipped, using: &admission)
        try encoder.field("limits", limits, using: &admission)
        try encoder.field("mode", mode, using: &admission)
        try encoder.field("tangentEdges", tangentEdges, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}
