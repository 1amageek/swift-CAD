import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SweepFeature`.
extension CADIR.SweepFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SweepFeature", fields: 5)
        try encoder.field("guides", guides)
        try encoder.field("options", options)
        try encoder.field("path", path)
        try encoder.field("sections", sections)
        try encoder.field("targets", targets)
    }
}
