import CADCore
import CADGeometry

/// Encodes original directed endpoints and their unrounded cyclic translation.
extension CADGeometry.OriginalParameterGain.Difference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.OriginalParameterGain.Difference", fields: 3, using: &admission)
        try encoder.field("originalLower", originalLower, using: &admission)
        try encoder.field("originalUpper", originalUpper, using: &admission)
        try encoder.field("periodicTranslation", periodicTranslation, using: &admission)
    }
}
