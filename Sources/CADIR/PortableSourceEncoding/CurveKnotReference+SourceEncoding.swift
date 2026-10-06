import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveKnotReference`.
extension CADIR.CurveKnotReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.CurveKnotReference", fields: 2)
        try encoder.field("curve", curve)
        try encoder.field("knotIndex", knotIndex)
    }
}
