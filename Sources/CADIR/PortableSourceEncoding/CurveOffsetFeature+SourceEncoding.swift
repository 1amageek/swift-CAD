import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveOffsetFeature`.
extension CADIR.CurveOffsetFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.CurveOffsetFeature", fields: 4)
        try encoder.field("distance", distance)
        try encoder.field("planeNormal", planeNormal)
        try encoder.field("side", side)
        try encoder.field("source", source)
    }
}
