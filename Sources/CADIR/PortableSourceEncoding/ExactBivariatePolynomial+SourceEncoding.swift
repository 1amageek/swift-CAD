import CADCore
import CADGeometry

extension ExactBivariatePolynomial: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.ExactBivariatePolynomial", fields: 1, using: &admission)
        try encoder.field("coefficients", originalCoefficients, using: &admission)
    }
}
