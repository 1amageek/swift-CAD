import CADCore

/// Encodes all original retained STEP placement fields.
extension OriginalSTEPPlacementElement: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.OriginalSTEPPlacementElement", fields: 3)
        try encoder.field("coordinates", coordinates)
        try encoder.field("id", id)
        try encoder.field("name", name)
    }
}
