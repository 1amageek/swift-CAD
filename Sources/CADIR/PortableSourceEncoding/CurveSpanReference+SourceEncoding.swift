import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveSpanReference`.
extension CADIR.CurveSpanReference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.CurveSpanReference", fields: 2, using: &admission)
        try encoder.field("curve", curve, using: &admission)
        try encoder.field("spanIndex", spanIndex, using: &admission)
    }
}
