import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SetbackCornerFeature`.
extension CADIR.SetbackCornerFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SetbackCornerFeature", fields: 3)
        try encoder.field("radius", radius)
        try encoder.field("target", target)
        try encoder.field("vertex", vertex)
    }
}
