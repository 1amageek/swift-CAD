import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.InvoluteGearFeature`.
extension CADIR.InvoluteGearFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.InvoluteGearFeature", fields: 5, using: &admission)
        try encoder.field("dimensions", dimensions, using: &admission)
        try encoder.field("doubleHelical", doubleHelical, using: &admission)
        try encoder.field("maximumSegments", maximumSegments, using: &admission)
        try encoder.field("origin", origin, using: &admission)
        try encoder.field("toothCount", toothCount, using: &admission)
    }
}
