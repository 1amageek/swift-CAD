/// Exact equation equivalence restricted to the retained nonzero denominator guards.
package struct OriginalGuardedIntersectionEquations: Sendable {
    package struct Division: Sendable {
        package let equationIndex: Int
        package let dividend: ExactIntersectionPolynomial
        package let factor: ExactIntersectionPolynomial
        package let quotient: ExactIntersectionPolynomial
        package let guardQuotient: ExactIntersectionPolynomial
    }

    package let originalEquations: [ExactIntersectionPolynomial]
    package let denominatorGuards: [ExactIntersectionPolynomial]
    package let guardProduct: ExactIntersectionPolynomial
    package let normalizedEquations: [ExactIntersectionPolynomial]
    package let divisions: [Division]

    package static func prepare<B: RationalAlgebraAdmitting>(equations: [ExactIntersectionPolynomial],
        denominatorGuards: [ExactIntersectionPolynomial], variableCount: Int, usage: inout B) throws -> Self {
        try intersectionAlgebraStep(&usage)
        var product = try ExactIntersectionPolynomial.constant(variableCount: variableCount, value: .one, usage: &usage)
        for guardPolynomial in denominatorGuards {
            guard !guardPolynomial.isZero else {
                throw rationalAlgebraFailure("Guarded equation normalization requires nonzero original denominator polynomials.")
            }
            product = try product.multiplied(by: guardPolynomial, usage: &usage)
        }
        try RationalAlgebraStorage.retain(equations.count, of: ExactIntersectionPolynomial.self, usage: &usage)
        var normalized: [ExactIntersectionPolynomial] = []; normalized.reserveCapacity(equations.count)
        var divisions: [Division] = []
        for (index, equation) in equations.enumerated() {
            try intersectionAlgebraStep(&usage)
            guard equation.variableCount == variableCount else {
                throw rationalAlgebraFailure("Guarded equations must retain the original parameter ring.")
            }
            var current = equation
            // A zero equation is already equivalent everywhere; dividing it by
            // the guard repeatedly would not decrease any polynomial degree.
            while !current.isZero {
                let factor = try ExactIntersectionPolynomialGCD.gcd(current, product, usage: &usage)
                if factor.isConstant { break }
                let quotient = try current.dividedExactly(by: factor, usage: &usage)
                let guardQuotient = try product.dividedExactly(by: factor, usage: &usage)
                // Both retained identities are checked in the original ring.
                guard try factor.multiplied(by: quotient, usage: &usage).matches(current, usage: &usage),
                    try factor.multiplied(by: guardQuotient, usage: &usage).matches(product, usage: &usage) else {
                    throw rationalAlgebraFailure("Guarded normalization lost an exact original division identity.")
                }
                try RationalAlgebraStorage.retain(1, of: Division.self, usage: &usage)
                divisions.append(.init(equationIndex: index, dividend: current, factor: factor,
                    quotient: quotient, guardQuotient: guardQuotient))
                current = quotient
            }
            normalized.append(current)
        }
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        return Self(originalEquations: equations, denominatorGuards: denominatorGuards,
            guardProduct: product, normalizedEquations: normalized, divisions: divisions)
    }
}
