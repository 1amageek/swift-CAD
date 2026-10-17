import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveControlPointEdit`.
extension CADIR.CurveControlPointEdit: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.CurveControlPointEdit", fields: 2, using: &admission)
        try encoder.field("point", point, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}
