extension ExactAlgebraicPairAuthority {
    func originalFiberNumerator<B: RationalAlgebraAdmitting>(usage: inout B) throws -> ExactBivariatePolynomial {
        var result = ExactBivariatePolynomial.zero
        for (degree, coefficient) in fiber.coefficients {
            var term = coefficient.numerator
            for (otherDegree, other) in fiber.coefficients where otherDegree != degree {
                term = try term.multiplied(by: other.denominator, usage: &usage)
            }
            try usage.retainExactStorage(1)
            let power = try ExactBivariatePolynomial([.init(u: 0, v: degree): .one])
            result = try result.adding(term.multiplied(by: power, usage: &usage), usage: &usage)
        }
        return result
    }

}
