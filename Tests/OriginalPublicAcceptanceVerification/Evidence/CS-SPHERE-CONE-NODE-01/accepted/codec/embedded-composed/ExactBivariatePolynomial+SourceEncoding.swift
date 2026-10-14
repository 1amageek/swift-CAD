import CADCore

extension ExactBivariatePolynomial: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.ExactBivariatePolynomial", fields: 1)
        try encoder.field("coefficients", originalCoefficients)
    }
}
