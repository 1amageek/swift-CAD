import CADCore

/// Encodes the complete authored flat placement factor sequence.
extension AssemblyPlacementWord: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.AssemblyPlacementWord", fields: 1)
        try encoder.field("factors", factors)
    }
}
