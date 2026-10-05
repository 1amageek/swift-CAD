import CADCore
import CADGeometry

extension ExactBivariatePolynomial.Power: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.ExactBivariatePolynomial.Power", fields: 2)
        try encoder.field("u", u)
        try encoder.field("v", v)
    }
}
