import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.LoftFeature`.
extension CADIR.LoftFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.LoftFeature", fields: 4, using: &admission)
        try encoder.field("apex", apex, using: &admission)
        try encoder.field("guides", guides, using: &admission)
        try encoder.field("options", options, using: &admission)
        try encoder.field("sections", sections, using: &admission)
    }
}
