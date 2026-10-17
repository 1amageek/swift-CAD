import CADCore

/// Encodes the complete original IGES lexical source and authored adjustments.
extension OriginalIGESPlacementAdjustment: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.OriginalIGESPlacementAdjustment", fields: 2, using: &admission)
        try encoder.field("conjugates", conjugates, using: &admission)
        try encoder.field("displacement", displacement, using: &admission)
    }
}
