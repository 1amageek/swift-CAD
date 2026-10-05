import CADCore

/// Encodes the complete original IGES lexical source and authored adjustments.
extension OriginalIGESPlacementAdjustment: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.OriginalIGESPlacementAdjustment", fields: 2)
        try encoder.field("conjugates", conjugates)
        try encoder.field("displacement", displacement)
    }
}
