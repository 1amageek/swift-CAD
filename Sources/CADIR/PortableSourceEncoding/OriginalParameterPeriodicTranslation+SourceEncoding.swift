import CADCore
import CADGeometry

/// Encodes the original period, integer turns and retained parameter gain law.
extension CADGeometry.OriginalParameterPeriodicTranslation: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.OriginalParameterPeriodicTranslation", fields: 3, using: &admission)
        try encoder.field("originalSourcePeriod", originalSourcePeriod, using: &admission)
        try encoder.field("originalTurnCount", originalTurnCount, using: &admission)
        try encoder.field("parameterGain", parameterGain, using: &admission)
    }
}
