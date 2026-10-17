import CADCore
import CADGeometry

/// Encodes the complete canonical original exact rational endpoint authority.
extension ExactRationalCoefficient: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.ExactRationalCoefficient", fields: 3, using: &admission)
        try encoder.field("sign", canonicalSign, using: &admission)
        try encoder.field("numeratorWords", canonicalNumeratorWords, using: &admission)
        try encoder.field("denominatorWords", canonicalDenominatorWords, using: &admission)
    }
}
