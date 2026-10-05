import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.InvoluteGearFeature`.
extension CADIR.InvoluteGearFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.InvoluteGearFeature", fields: 5)
        try encoder.field("dimensions", dimensions)
        try encoder.field("doubleHelical", doubleHelical)
        try encoder.field("maximumSegments", maximumSegments)
        try encoder.field("origin", origin)
        try encoder.field("toothCount", toothCount)
    }
}
