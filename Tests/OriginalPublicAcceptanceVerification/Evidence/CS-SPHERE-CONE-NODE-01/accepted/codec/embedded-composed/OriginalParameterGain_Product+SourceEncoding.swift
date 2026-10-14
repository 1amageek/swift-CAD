import CADCore

/// Encodes original source fields owned by `CADGeometry.OriginalParameterGain.Product`.
extension CADGeometry.OriginalParameterGain.Product: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.OriginalParameterGain.Product", fields: 1)
        try encoder.field("factors", factors)
    }
}
