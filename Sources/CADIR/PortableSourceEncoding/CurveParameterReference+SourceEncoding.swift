import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveParameterReference`.
extension CADIR.CurveParameterReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.CurveParameterReference", fields: 2)
        try encoder.field("curve", curve)
        try encoder.field("parameter", parameter)
    }
}
