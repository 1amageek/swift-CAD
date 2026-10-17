import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SetbackCornerFeature`.
extension CADIR.SetbackCornerFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SetbackCornerFeature", fields: 3, using: &admission)
        try encoder.field("radius", radius, using: &admission)
        try encoder.field("target", target, using: &admission)
        try encoder.field("vertex", vertex, using: &admission)
    }
}
