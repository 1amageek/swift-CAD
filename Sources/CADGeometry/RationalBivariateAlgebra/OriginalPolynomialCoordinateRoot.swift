/// Polynomial coordinates use the same original rational transport authority with W=1.
package struct OriginalPolynomialCoordinateRoot {
    package static func coordinate<B: RationalAlgebraAdmitting>(_ original: ExactBivariatePolynomial,
        at endpoint: ExactMonotoneGraphEndpoint, maximumDepth: Int,
        usage: inout B) throws -> ExactMonotoneGraphEndpoint {
        try OriginalRationalCoordinateRoot.coordinate(numerator: original,
            denominator: .constant(.one, usage: &usage), at: endpoint,
            maximumDepth: maximumDepth, usage: &usage)
    }
}
