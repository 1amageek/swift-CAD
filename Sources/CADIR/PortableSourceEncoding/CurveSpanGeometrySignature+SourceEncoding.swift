import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveSpanGeometrySignature`.
extension CADIR.CurveSpanGeometrySignature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.CurveSpanGeometrySignature", fields: 5, using: &admission)
        try encoder.field("curve", curve, using: &admission)
        try encoder.field("endParameter", endParameter, using: &admission)
        try encoder.field("endPoint", endPoint, using: &admission)
        try encoder.field("startParameter", startParameter, using: &admission)
        try encoder.field("startPoint", startPoint, using: &admission)
    }
}
