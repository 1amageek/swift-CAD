import CADCore

/// Encodes all original retained STEP placement fields.
extension OriginalSTEPPlacementElement: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.OriginalSTEPPlacementElement", fields: 3, using: &admission)
        try encoder.field("coordinates", coordinates, using: &admission)
        try encoder.field("id", id, using: &admission)
        try encoder.field("name", name, using: &admission)
    }
}
