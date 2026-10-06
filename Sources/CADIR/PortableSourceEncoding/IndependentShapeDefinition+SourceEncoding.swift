import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeDefinition`.
extension CADIR.IndependentShapeDefinition: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.IndependentShapeDefinition", fields: 4)
        try encoder.field("id", id)
        try encoder.field("originFrameID", originFrameID)
        try encoder.field("originalIGES", originalIGES)
        try encoder.field("representationID", representationID)
    }
}
