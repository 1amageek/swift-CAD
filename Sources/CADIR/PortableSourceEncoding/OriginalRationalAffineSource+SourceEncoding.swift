import CADCore
import CADGeometry

/// Encodes all twelve original rational affine coefficients without a derived frame.
extension OriginalRationalAffineSource: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.OriginalRationalAffineSource", fields: 1)
        try encoder.field("coefficients", coefficients)
    }
}
