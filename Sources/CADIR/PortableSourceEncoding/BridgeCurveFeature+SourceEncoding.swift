import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.BridgeCurveFeature`.
extension CADIR.BridgeCurveFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.BridgeCurveFeature", fields: 3)
        try encoder.field("continuityTolerances", continuityTolerances)
        try encoder.field("end", end)
        try encoder.field("start", start)
    }
}
