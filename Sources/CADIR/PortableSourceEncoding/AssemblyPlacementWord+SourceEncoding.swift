import CADCore

/// Encodes the complete authored flat placement factor sequence.
extension AssemblyPlacementWord: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.AssemblyPlacementWord", fields: 1, using: &admission)
        try encoder.field("factors", factors, using: &admission)
    }
}
