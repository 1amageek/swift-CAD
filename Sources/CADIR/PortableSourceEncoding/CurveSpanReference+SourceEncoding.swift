import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveSpanReference`.
extension CADIR.CurveSpanReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.CurveSpanReference", fields: 2)
        try encoder.field("curve", curve)
        try encoder.field("spanIndex", spanIndex)
    }
}
