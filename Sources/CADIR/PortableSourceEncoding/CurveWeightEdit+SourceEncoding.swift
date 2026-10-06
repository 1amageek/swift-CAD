import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveWeightEdit`.
extension CADIR.CurveWeightEdit: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.CurveWeightEdit", fields: 2)
        try encoder.field("target", target)
        try encoder.field("value", value)
    }
}
