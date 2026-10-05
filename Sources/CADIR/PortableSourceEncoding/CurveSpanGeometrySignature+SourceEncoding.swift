import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveSpanGeometrySignature`.
extension CADIR.CurveSpanGeometrySignature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.CurveSpanGeometrySignature", fields: 5)
        try encoder.field("curve", curve)
        try encoder.field("endParameter", endParameter)
        try encoder.field("endPoint", endPoint)
        try encoder.field("startParameter", startParameter)
        try encoder.field("startPoint", startPoint)
    }
}
