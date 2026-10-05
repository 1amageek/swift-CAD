import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.EdgeCurveFeature`.
extension CADIR.EdgeCurveFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.EdgeCurveFeature", fields: 3)
        try encoder.field("bodyRole", bodyRole)
        try encoder.field("edges", edges)
        try encoder.field("source", source)
    }
}
