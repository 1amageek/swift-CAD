import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.G2BlendFeature`.
extension CADIR.G2BlendFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.G2BlendFeature", fields: 3, using: &admission)
        try encoder.field("distance", distance, using: &admission)
        try encoder.field("edges", edges, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}
