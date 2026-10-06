import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceOffsetFeature`.
extension CADIR.SurfaceOffsetFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SurfaceOffsetFeature", fields: 2)
        try encoder.field("distance", distance)
        try encoder.field("target", target)
    }
}
