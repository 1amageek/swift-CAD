import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceMatchFeature`.
extension CADIR.SurfaceMatchFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SurfaceMatchFeature", fields: 6)
        try encoder.field("continuity", continuity)
        try encoder.field("normalAlignment", normalAlignment)
        try encoder.field("source", source)
        try encoder.field("sourceParameter", sourceParameter)
        try encoder.field("target", target)
        try encoder.field("targetParameter", targetParameter)
    }
}
