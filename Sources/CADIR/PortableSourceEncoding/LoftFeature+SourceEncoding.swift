import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.LoftFeature`.
extension CADIR.LoftFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.LoftFeature", fields: 4)
        try encoder.field("apex", apex)
        try encoder.field("guides", guides)
        try encoder.field("options", options)
        try encoder.field("sections", sections)
    }
}
