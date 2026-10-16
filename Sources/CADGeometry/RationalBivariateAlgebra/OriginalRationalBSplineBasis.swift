import CADCore

/// Exact original Cox-de Boor basis on one validated selected positive span.
package struct OriginalRationalBSplineBasis {
    package static func powerPolynomials<B: ExactScalarAdmission & ~Copyable>(knots: [Double], degree: Int, span: Int, alongU: Bool,
        translation: Double, usage: inout B) throws -> [Int: ExactBivariatePolynomial] {
        let highIndex = try rationalAlgebraCount(try rationalAlgebraCount(span, degree), 1)
        guard degree >= 0, span >= degree, highIndex < knots.count,
              knots[span] < knots[span + 1] else {
            throw rationalAlgebraFailure("Original rational basis requires its validated positive native span.")
        }
        let parameter = try ExactBivariatePolynomial.coordinate(alongU: alongU, usage: &usage)
            .subtracting(.constant(.originalDouble(translation, usage: &usage), usage: &usage), usage: &usage)
        try RationalAlgebraStorage.retain(1, of: (Int, ExactBivariatePolynomial).self, usage: &usage)
        var current = [span: try ExactBivariatePolynomial.constant(.one, usage: &usage)]
        if degree == 0 { return current }
        for order in 1...degree {
            var next: [Int: ExactBivariatePolynomial] = [:]
            for index in (span - order)...span {
                var polynomial = ExactBivariatePolynomial.zero
                if let left = current[index] {
                    let low = try ExactRationalCoefficient.originalDouble(knots[index], usage: &usage)
                    let high = try ExactRationalCoefficient.originalDouble(knots[index + order], usage: &usage)
                    let denominator = try high.subtracting(low, usage: &usage)
                    if !denominator.isZero {
                        polynomial = try parameter.subtracting(.constant(low, usage: &usage), usage: &usage)
                            .multiplied(by: left, usage: &usage)
                            .scaled(by: .one.divided(by: denominator, usage: &usage), usage: &usage)
                    }
                }
                if let right = current[index + 1] {
                    let low = try ExactRationalCoefficient.originalDouble(knots[index + 1], usage: &usage)
                    let high = try ExactRationalCoefficient.originalDouble(knots[index + order + 1], usage: &usage)
                    let denominator = try high.subtracting(low, usage: &usage)
                    if !denominator.isZero {
                        let term = try ExactBivariatePolynomial.constant(high, usage: &usage)
                            .subtracting(parameter, usage: &usage).multiplied(by: right, usage: &usage)
                            .scaled(by: .one.divided(by: denominator, usage: &usage), usage: &usage)
                        polynomial = try polynomial.adding(term, usage: &usage)
                    }
                }
                try RationalAlgebraStorage.retain(1, of: (Int, ExactBivariatePolynomial).self, usage: &usage); next[index] = polynomial
            }
            current = next
        }
        return current
    }
}
