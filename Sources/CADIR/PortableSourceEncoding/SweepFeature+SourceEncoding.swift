import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SweepFeature`.
extension CADIR.SweepFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SweepFeature", fields: 5, using: &admission)
        try encoder.field("guides", guides, using: &admission)
        try encoder.field("options", options, using: &admission)
        try encoder.field("path", path, using: &admission)
        try encoder.field("sections", sections, using: &admission)
        try encoder.field("targets", targets, using: &admission)
    }
}
