import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeDefinition`.
extension CADIR.IndependentShapeDefinition: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.IndependentShapeDefinition", fields: 4, using: &admission)
        try encoder.field("id", id, using: &admission)
        try encoder.field("originFrameID", originFrameID, using: &admission)
        try encoder.field("originalIGES", originalIGES, using: &admission)
        try encoder.field("representationID", representationID, using: &admission)
    }
}
