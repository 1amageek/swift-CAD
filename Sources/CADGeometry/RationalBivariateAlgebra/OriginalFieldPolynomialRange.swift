/// Exact Bernstein convex-hull bounds over one retained ordered coefficient field.
package struct OriginalFieldPolynomialRange: Sendable {
    package let lower: OriginalSingularFieldElement
    package let upper: OriginalSingularFieldElement

    package init<B: ExactScalarAdmission & ~Copyable>(original: OriginalSingularFieldPlanePolynomial,
        lower: ExactRationalCoefficient, upper: ExactRationalCoefficient,
        maximumDepth: Int, usage: inout B) throws {
        guard original.vDegree <= 0, !(try upper.subtracting(lower, usage: &usage)).isNegative else {
            throw rationalAlgebraFailure("Original field range needs an ordered univariate rational domain.")
        }
        let context = original.context
        let zero = try OriginalSingularFieldElement.constant(.zero, in: context,
            maximumDepth: maximumDepth, usage: &usage)
        if original.isZero { self.lower = zero; self.upper = zero; return }
        let origin = try OriginalSingularFieldElement.constant(lower, in: context,
            maximumDepth: maximumDepth, usage: &usage)
        if lower == upper {
            let value = try original.evaluated(atU: origin, v: zero,
                maximumDepth: maximumDepth, usage: &usage)
            self.lower = value; self.upper = value; return
        }
        let width = try OriginalSingularFieldElement.constant(upper.subtracting(lower, usage: &usage),
            in: context, maximumDepth: maximumDepth, usage: &usage)
        let coordinate = try OriginalSingularFieldPlanePolynomial.coordinate(alongU: true,
            in: context, maximumDepth: maximumDepth, usage: &usage)
            .multiplied(by: .constant(width, maximumDepth: maximumDepth, usage: &usage),
                maximumDepth: maximumDepth, usage: &usage)
            .adding(.constant(origin, maximumDepth: maximumDepth, usage: &usage),
                maximumDepth: maximumDepth, usage: &usage)
        let local = try original.composed(withU: coordinate,
            v: .constant(zero, maximumDepth: maximumDepth, usage: &usage),
            maximumDepth: maximumDepth, usage: &usage)
        let degree = max(0, local.uDegree), count = try rationalAlgebraCount(max(0, local.uDegree), 1)
        try RationalAlgebraStorage.retain(count, of: OriginalSingularFieldElement.self, usage: &usage)
        var powers = [OriginalSingularFieldElement](repeating: zero, count: count)
        for term in try local.orderedTerms(usage: &usage) {
            try usage.consumeWork(1)
            guard term.key.v == 0 else { throw rationalAlgebraFailure("Original field curve has a second parameter.") }
            powers[term.key.u] = term.value
        }
        var minimum: OriginalSingularFieldElement?, maximum: OriginalSingularFieldElement?
        for index in 0...degree {
            var value = zero, ratio = ExactRationalCoefficient.one
            for power in 0...index {
                try usage.consumeWork(1)
                let scale = try OriginalSingularFieldElement.constant(ratio, in: context,
                    maximumDepth: maximumDepth, usage: &usage)
                value = try value.adding(powers[power].multiplied(by: scale,
                    maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
                if power < index {
                    ratio = try ratio.multiplied(by: .natural(index - power, usage: &usage), usage: &usage)
                        .divided(by: .natural(degree - power, usage: &usage), usage: &usage)
                }
            }
            if let prior = minimum {
                if case .negative = try value.subtracting(prior, maximumDepth: maximumDepth, usage: &usage)
                    .sign(maximumDepth: maximumDepth, usage: &usage) { minimum = value }
            } else { minimum = value }
            if let prior = maximum {
                if case .positive = try value.subtracting(prior, maximumDepth: maximumDepth, usage: &usage)
                    .sign(maximumDepth: maximumDepth, usage: &usage) { maximum = value }
            } else { maximum = value }
        }
        guard let minimum, let maximum else { throw rationalAlgebraFailure("Original field Bernstein controls were omitted.") }
        self.lower = minimum; self.upper = maximum
    }

    private init(lower: OriginalSingularFieldElement, upper: OriginalSingularFieldElement) {
        self.lower = lower; self.upper = upper
    }

    package func divided<B: ExactScalarAdmission & ~Copyable>(by positive: Self,
        maximumDepth: Int, usage: inout B) throws -> Self {
        guard lower.context === positive.lower.context,
              case .positive = try positive.lower.sign(maximumDepth: maximumDepth, usage: &usage) else {
            throw rationalAlgebraFailure("Original homogeneous field weight has no strictly positive bound.")
        }
        var minimum = try lower.divided(by: positive.lower, maximumDepth: maximumDepth, usage: &usage)
        var maximum = minimum
        for corner in 1...3 {
            try usage.consumeWork(1)
            let numerator = corner < 2 ? lower : upper
            let denominator = corner & 1 == 0 ? positive.lower : positive.upper
            let value = try numerator.divided(by: denominator, maximumDepth: maximumDepth, usage: &usage)
            if case .negative = try value.subtracting(minimum, maximumDepth: maximumDepth, usage: &usage)
                .sign(maximumDepth: maximumDepth, usage: &usage) { minimum = value }
            if case .positive = try value.subtracting(maximum, maximumDepth: maximumDepth, usage: &usage)
                .sign(maximumDepth: maximumDepth, usage: &usage) { maximum = value }
        }
        return Self(lower: minimum, upper: maximum)
    }

    package func outward<B: ExactScalarAdmission & ~Copyable>(maximumCoefficientWidth: ExactRationalCoefficient,
        maximumDepth: Int, usage: inout B) throws -> OutwardScalarInterval {
        let a = try lower.enclosure(maximumWidth: maximumCoefficientWidth,
            maximumDepth: maximumDepth, usage: &usage)
        let b = try upper.enclosure(maximumWidth: maximumCoefficientWidth,
            maximumDepth: maximumDepth, usage: &usage)
        return OutwardScalarInterval(lower: a.lower, upper: b.upper)
    }
}
