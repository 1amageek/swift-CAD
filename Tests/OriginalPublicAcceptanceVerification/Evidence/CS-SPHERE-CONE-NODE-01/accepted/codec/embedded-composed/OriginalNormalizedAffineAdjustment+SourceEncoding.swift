import CADCore

/// Encodes original source fields; prepared geometry remains derived.
extension OriginalNormalizedAffineAdjustment: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.OriginalNormalizedAffineAdjustment", fields: 2)
        try encoder.field("conjugates", conjugates)
        try encoder.field("displacement", displacement)
    }
}
