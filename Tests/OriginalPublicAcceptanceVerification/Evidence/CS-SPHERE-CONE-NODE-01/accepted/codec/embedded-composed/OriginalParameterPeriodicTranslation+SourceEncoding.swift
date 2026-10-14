import CADCore

/// Encodes the original period, integer turns and retained parameter gain law.
extension CADGeometry.OriginalParameterPeriodicTranslation: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.OriginalParameterPeriodicTranslation", fields: 3)
        try encoder.field("originalSourcePeriod", originalSourcePeriod)
        try encoder.field("originalTurnCount", originalTurnCount)
        try encoder.field("parameterGain", parameterGain)
    }
}
