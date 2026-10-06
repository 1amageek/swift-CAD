import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveExtendFeature`.
extension CADIR.CurveExtendFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.CurveExtendFeature", fields: 3)
        try encoder.field("distance", distance)
        try encoder.field("end", end)
        try encoder.field("source", source)
    }
}
