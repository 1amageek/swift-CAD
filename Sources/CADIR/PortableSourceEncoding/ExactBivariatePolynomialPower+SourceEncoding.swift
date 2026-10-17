import CADCore
import CADGeometry

extension ExactBivariatePolynomial.Power: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.ExactBivariatePolynomial.Power", fields: 2, using: &admission)
        try encoder.field("u", u, using: &admission)
        try encoder.field("v", v, using: &admission)
    }
}
