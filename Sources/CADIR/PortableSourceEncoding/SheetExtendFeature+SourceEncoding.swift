import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SheetExtendFeature`.
extension CADIR.SheetExtendFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SheetExtendFeature", fields: 6)
        try encoder.field("distance", distance)
        try encoder.field("edges", edges)
        try encoder.field("limit", limit)
        try encoder.field("modifies", modifies)
        try encoder.field("shape", shape)
        try encoder.field("target", target)
    }
}
