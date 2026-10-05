import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveControlPointEdit`.
extension CADIR.CurveControlPointEdit: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.CurveControlPointEdit", fields: 2)
        try encoder.field("point", point)
        try encoder.field("target", target)
    }
}
