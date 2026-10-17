import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ImprintCurveReference`.
extension CADIR.ImprintCurveReference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.ImprintCurveReference", fields: 2, using: &admission)
        try encoder.field("curve", curve, using: &admission)
        try encoder.field("placement", placement, using: &admission)
    }
}
