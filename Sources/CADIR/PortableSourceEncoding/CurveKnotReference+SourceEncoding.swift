import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveKnotReference`.
extension CADIR.CurveKnotReference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.CurveKnotReference", fields: 2, using: &admission)
        try encoder.field("curve", curve, using: &admission)
        try encoder.field("knotIndex", knotIndex, using: &admission)
    }
}
