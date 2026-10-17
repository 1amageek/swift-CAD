import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.EdgeCurveFeature`.
extension CADIR.EdgeCurveFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.EdgeCurveFeature", fields: 3, using: &admission)
        try encoder.field("bodyRole", bodyRole, using: &admission)
        try encoder.field("edges", edges, using: &admission)
        try encoder.field("source", source, using: &admission)
    }
}
