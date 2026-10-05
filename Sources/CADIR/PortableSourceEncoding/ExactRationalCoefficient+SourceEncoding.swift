import CADCore
import CADGeometry

/// Encodes the complete canonical original exact rational endpoint authority.
extension ExactRationalCoefficient: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.ExactRationalCoefficient", fields: 3)
        try encoder.field("sign", canonicalSign)
        try encoder.field("numeratorWords", canonicalNumeratorWords)
        try encoder.field("denominatorWords", canonicalDenominatorWords)
    }
}
