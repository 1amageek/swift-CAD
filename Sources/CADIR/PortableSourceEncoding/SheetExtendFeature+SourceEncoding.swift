import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SheetExtendFeature`.
extension CADIR.SheetExtendFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SheetExtendFeature", fields: 6, using: &admission)
        try encoder.field("distance", distance, using: &admission)
        try encoder.field("edges", edges, using: &admission)
        try encoder.field("limit", limit, using: &admission)
        try encoder.field("modifies", modifies, using: &admission)
        try encoder.field("shape", shape, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}
