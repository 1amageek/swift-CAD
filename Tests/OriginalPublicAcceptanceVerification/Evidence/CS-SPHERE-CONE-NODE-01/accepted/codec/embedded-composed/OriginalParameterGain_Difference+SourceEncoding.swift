import CADCore

/// Encodes original directed endpoints and their unrounded cyclic translation.
extension CADGeometry.OriginalParameterGain.Difference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.OriginalParameterGain.Difference", fields: 3)
        try encoder.field("originalLower", originalLower)
        try encoder.field("originalUpper", originalUpper)
        try encoder.field("periodicTranslation", periodicTranslation)
    }
}
