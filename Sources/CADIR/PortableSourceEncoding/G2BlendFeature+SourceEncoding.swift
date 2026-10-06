import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.G2BlendFeature`.
extension CADIR.G2BlendFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.G2BlendFeature", fields: 3)
        try encoder.field("distance", distance)
        try encoder.field("edges", edges)
        try encoder.field("target", target)
    }
}
