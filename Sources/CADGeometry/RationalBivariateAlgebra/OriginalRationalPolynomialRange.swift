/// Exact Bernstein convex-hull bounds on one closed rational univariate domain.
package struct OriginalRationalPolynomialRange: Sendable {
    package let lower: ExactRationalCoefficient
    package let upper: ExactRationalCoefficient

    package init<B: RationalAlgebraAdmitting>(original: ExactBivariatePolynomial,
        lower: ExactRationalCoefficient, upper: ExactRationalCoefficient,
        usage: inout B) throws {
        guard original.vDegree <= 0, !(try upper.subtracting(lower, usage: &usage)).isNegative else {
            throw rationalAlgebraFailure("Original polynomial range requires an ordered univariate rational domain.")
        }
        if original.isZero { self.lower = .zero; self.upper = .zero; return }
        if lower == upper {
            let value = try original.evaluated(atU: lower, v: .zero, usage: &usage)
            self.lower = value; self.upper = value; return
        }
        let width = try upper.subtracting(lower, usage: &usage)
        let coordinate = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
            .scaled(by: width, usage: &usage)
            .adding(.constant(lower, usage: &usage), usage: &usage)
        let local = try original.composed(withU: coordinate, v: .zero, usage: &usage)
        let degree = max(0, local.uDegree)
        let count = try rationalAlgebraCount(degree, 1)
        try RationalAlgebraStorage.retain(count, of: ExactRationalCoefficient.self, usage: &usage)
        var powers = [ExactRationalCoefficient](repeating: .zero, count: count)
        for term in try local.orderedTerms(usage: &usage) {
            try usage.consumeExactWork(1)
            guard term.key.v == 0 else { throw rationalAlgebraFailure("Original curve range contains a second parameter.") }
            powers[term.key.u] = term.value
        }
        var minimum: ExactRationalCoefficient?, maximum: ExactRationalCoefficient?
        for index in 0...degree {
            var value = ExactRationalCoefficient.zero
            var ratio = ExactRationalCoefficient.one
            for power in 0...index {
                try usage.consumeExactWork(1)
                value = try value.adding(powers[power].multiplied(by: ratio, usage: &usage), usage: &usage)
                if power < index {
                    ratio = try ratio.multiplied(by: .natural(index - power, usage: &usage), usage: &usage)
                        .divided(by: .natural(degree - power, usage: &usage), usage: &usage)
                }
            }
            if let prior = minimum {
                if try value.subtracting(prior, usage: &usage).isNegative { minimum = value }
            } else { minimum = value }
            if let prior = maximum {
                if try value.subtracting(prior, usage: &usage).isPositive { maximum = value }
            } else { maximum = value }
        }
        guard let minimum, let maximum else { throw rationalAlgebraFailure("Original Bernstein range omitted its coefficients.") }
        self.lower = minimum; self.upper = maximum
    }

    private init(lower: ExactRationalCoefficient, upper: ExactRationalCoefficient) {
        self.lower = lower; self.upper = upper
    }

    package func divided<B: RationalAlgebraAdmitting>(by positive: Self,
        usage: inout B) throws -> Self {
        guard positive.lower.isPositive else {
            throw rationalAlgebraFailure("Original rational curve weight range is not strictly positive.")
        }
        var minimum = try lower.divided(by: positive.lower, usage: &usage)
        var maximum = minimum
        // Fixed scalar traversal avoids a temporary quotient-corner array.
        for corner in 1...3 {
            try usage.consumeExactWork(1)
            let numerator = corner < 2 ? lower : upper
            let denominator = corner & 1 == 0 ? positive.lower : positive.upper
            let value = try numerator.divided(by: denominator, usage: &usage)
            if try value.subtracting(minimum, usage: &usage).isNegative { minimum = value }
            if try value.subtracting(maximum, usage: &usage).isPositive { maximum = value }
        }
        return Self(lower: minimum, upper: maximum)
    }

    package func scaled<B: RationalAlgebraAdmitting>(by gain: ExactRationalCoefficient,
        usage: inout B) throws -> Self {
        let a = try lower.multiplied(by: gain, usage: &usage)
        let b = try upper.multiplied(by: gain, usage: &usage)
        return gain.isNegative ? Self(lower: b, upper: a) : Self(lower: a, upper: b)
    }

    package func outward<B: RationalAlgebraAdmitting>(usage: inout B) throws -> OutwardScalarInterval {
        let a = try lower.outwardInterval(usage: &usage)
        let b = try upper.outwardInterval(usage: &usage)
        return OutwardScalarInterval(lower: a.lower, upper: b.upper)
    }
}
