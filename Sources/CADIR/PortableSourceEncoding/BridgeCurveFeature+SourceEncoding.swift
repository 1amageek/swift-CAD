import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.BridgeCurveFeature`.
extension CADIR.BridgeCurveFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.BridgeCurveFeature", fields: 3, using: &admission)
        try encoder.field("continuityTolerances", continuityTolerances, using: &admission)
        try encoder.field("end", end, using: &admission)
        try encoder.field("start", start, using: &admission)
    }
}
