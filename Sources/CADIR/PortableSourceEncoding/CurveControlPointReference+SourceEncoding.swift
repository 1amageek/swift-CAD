import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveControlPointReference`.
extension CADIR.CurveControlPointReference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.CurveControlPointReference", fields: 2, using: &admission)
        try encoder.field("controlPointIndex", controlPointIndex, using: &admission)
        try encoder.field("curve", curve, using: &admission)
    }
}
