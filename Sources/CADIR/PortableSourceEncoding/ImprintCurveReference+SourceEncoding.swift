import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ImprintCurveReference`.
extension CADIR.ImprintCurveReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ImprintCurveReference", fields: 2)
        try encoder.field("curve", curve)
        try encoder.field("placement", placement)
    }
}
