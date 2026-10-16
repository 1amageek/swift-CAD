/// Complete original coordinate-product zero law; general residuals are distinct.
package struct OriginalRationalCoordinateZeroFactors: Sendable {
    package let original: ExactBivariatePolynomial
    package let uFactor: ExactBivariatePolynomial
    package let vFactor: ExactBivariatePolynomial
    package let scalar: ExactRationalCoefficient

    package static func proven<B: ExactScalarAdmission & ~Copyable>(original: ExactBivariatePolynomial,
        usage: inout B) throws -> Self? {
        guard !original.isZero else { return nil }
        let gcd = ExactBivariateGCD()
        var u = ExactBivariatePolynomial.zero
        for degree in 0...original.vDegree {
            let coefficient = try original.coefficient(ofV: degree, usage: &usage)
            u = try gcd.univariateGCD(u, coefficient, usage: &usage)
        }
        guard u.uDegree > 0 else { return nil }
        let remaining = try original.dividedExactly(by: u, usage: &usage)
        let exchanged = try remaining.exchangedAxes(usage: &usage)
        var v = ExactBivariatePolynomial.zero
        for degree in 0...exchanged.vDegree {
            v = try gcd.univariateGCD(v, exchanged.coefficient(ofV: degree, usage: &usage), usage: &usage)
        }
        guard v.uDegree > 0 else { return nil }
        let residual = try exchanged.dividedExactly(by: v, usage: &usage)
        guard residual.uDegree <= 0, residual.vDegree <= 0 else { return nil }
        let scalar = try residual.evaluated(atU: .zero, v: .zero, usage: &usage)
        guard !scalar.isZero else { throw rationalAlgebraFailure("Original coordinate factor identity lost its nonzero scalar.") }
        let nativeV = try v.exchangedAxes(usage: &usage)
        guard try u.multiplied(by: nativeV, usage: &usage).scaled(by: scalar, usage: &usage)
            .subtracting(original, usage: &usage).isZero else {
            throw rationalAlgebraFailure("Original coordinate factorization does not reconstruct the actual source.")
        }
        return Self(original: original, uFactor: u, vFactor: nativeV, scalar: scalar)
    }

    package func roots<B: ExactScalarAdmission & ~Copyable>(alongU: Bool, over interval: ScalarInterval,
        maximumDepth: Int, usage: inout B) throws -> [ExactMonotoneGraphEndpoint] {
        let polynomial = alongU ? uFactor : try vFactor.exchangedAxes(usage: &usage)
        let isolated = try ExactUnivariateRootIsolator().isolate(polynomial,
            lower: .originalDouble(interval.lower, usage: &usage),
            upper: .originalDouble(interval.upper, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
        var result: [ExactMonotoneGraphEndpoint] = []
        for isolation in isolated {
            try RationalAlgebraStorage.retain(1, of: ExactMonotoneGraphEndpoint.self, usage: &usage)
            result.append(try .algebraic(ExactAlgebraicRealRoot(polynomial: polynomial,
                isolation: isolation, usage: &usage)))
        }
        return result
    }
}
