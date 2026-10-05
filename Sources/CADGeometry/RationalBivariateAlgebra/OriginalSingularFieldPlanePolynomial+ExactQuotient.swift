extension OriginalSingularFieldPlanePolynomial {
    package func quotientAndRemainder<B: RationalAlgebraAdmitting>(dividingBy divisor: Self,
        maximumDepth: Int, usage: inout B) throws -> (quotient: Self, remainder: Self) {
        guard context === divisor.context, let leading = try divisor.leading(usage: &usage) else {
            throw rationalAlgebraFailure("Original plane division needs one field and nonzero divisor.")
        }
        var pending = self
        var quotient = try Self(context: context, coefficients: [:], maximumDepth: maximumDepth, usage: &usage)
        var remainder = quotient
        while let next = try pending.leading(usage: &usage) {
            try usage.consumeExactWork(1)
            if next.key.u >= leading.key.u, next.key.v >= leading.key.v {
                let term = try Self.monomial(u: next.key.u - leading.key.u, v: next.key.v - leading.key.v,
                    coefficient: next.value.divided(by: leading.value, maximumDepth: maximumDepth, usage: &usage),
                    maximumDepth: maximumDepth, usage: &usage)
                quotient = try quotient.adding(term, maximumDepth: maximumDepth, usage: &usage)
                pending = try pending.subtracting(divisor.multiplied(by: term, maximumDepth: maximumDepth, usage: &usage),
                    maximumDepth: maximumDepth, usage: &usage)
            } else {
                let term = try Self.monomial(u: next.key.u, v: next.key.v, coefficient: next.value,
                    maximumDepth: maximumDepth, usage: &usage)
                remainder = try remainder.adding(term, maximumDepth: maximumDepth, usage: &usage)
                pending = try pending.subtracting(term, maximumDepth: maximumDepth, usage: &usage)
            }
            if let remaining = try pending.leading(usage: &usage) {
                guard remaining.key.v < next.key.v || remaining.key.v == next.key.v && remaining.key.u < next.key.u else {
                    throw rationalAlgebraFailure("Original ordered-field division failed to reduce its leading power.")
                }
            }
        }
        try RationalAlgebraStorage.retain(1, of: (Self, Self).self, usage: &usage)
        return (quotient, remainder)
    }

    package func dividedExactly<B: RationalAlgebraAdmitting>(by divisor: Self,
        maximumDepth: Int, usage: inout B) throws -> Self {
        let division = try quotientAndRemainder(dividingBy: divisor, maximumDepth: maximumDepth, usage: &usage)
        guard division.remainder.isZero else {
            throw rationalAlgebraFailure("Original plane divisor does not divide its source exactly.")
        }
        return division.quotient
    }
}
