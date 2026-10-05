import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveControlPointReference`.
extension CADIR.CurveControlPointReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.CurveControlPointReference", fields: 2)
        try encoder.field("controlPointIndex", controlPointIndex)
        try encoder.field("curve", curve)
    }
}
