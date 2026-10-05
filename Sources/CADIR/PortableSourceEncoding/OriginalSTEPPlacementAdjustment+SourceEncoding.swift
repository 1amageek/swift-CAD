import CADCore

/// Encodes the original ordered displacement operation and its family.
extension OriginalSTEPPlacementAdjustment: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.OriginalSTEPPlacementAdjustment", fields: 2)
        try encoder.field("conjugates", conjugates)
        try encoder.field("displacement", displacement)
    }
}
