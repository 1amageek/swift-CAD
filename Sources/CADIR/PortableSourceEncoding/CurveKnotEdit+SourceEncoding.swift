import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveKnotEdit`.
extension CADIR.CurveKnotEdit: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.CurveKnotEdit", fields: 2)
        try encoder.field("target", target)
        try encoder.field("value", value)
    }
}
