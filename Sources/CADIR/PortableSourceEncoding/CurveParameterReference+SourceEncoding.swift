import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveParameterReference`.
extension CADIR.CurveParameterReference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.CurveParameterReference", fields: 2, using: &admission)
        try encoder.field("curve", curve, using: &admission)
        try encoder.field("parameter", parameter, using: &admission)
    }
}
