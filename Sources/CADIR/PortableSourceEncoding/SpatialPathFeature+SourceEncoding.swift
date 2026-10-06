import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SpatialPathFeature`.
extension CADIR.SpatialPathFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SpatialPathFeature", fields: 3)
        try encoder.field("isClosed", isClosed)
        try encoder.field("kind", kind)
        try encoder.field("knots", knots)
    }
}
