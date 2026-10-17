import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveKnotEdit`.
extension CADIR.CurveKnotEdit: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.CurveKnotEdit", fields: 2, using: &admission)
        try encoder.field("target", target, using: &admission)
        try encoder.field("value", value, using: &admission)
    }
}
