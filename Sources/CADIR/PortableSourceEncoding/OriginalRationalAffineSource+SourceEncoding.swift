import CADCore
import CADGeometry

/// Encodes all twelve original rational affine coefficients without a derived frame.
extension OriginalRationalAffineSource: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.OriginalRationalAffineSource", fields: 1, using: &admission)
        try encoder.field("coefficients", coefficients, using: &admission)
    }
}
