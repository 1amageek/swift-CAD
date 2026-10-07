/// Original exact polynomial substitution, preserving actual coefficient identity.
extension ExactBivariatePolynomial {
    package func composed<B: RationalAlgebraAdmitting>(withU u: Self, v: Self,
        usage: inout B) throws -> Self {
        func power(_ source: Self, _ exponent: Int, usage: inout B) throws -> Self {
            var remaining = exponent, factor = source
            var result = try Self.constant(.one, usage: &usage)
            while remaining > 0 {
                try usage.consumeExactWork(1)
                if remaining % 2 == 1 { result = try result.multiplied(by: factor, usage: &usage) }
                remaining /= 2
                if remaining > 0 { factor = try factor.multiplied(by: factor, usage: &usage) }
            }
            return result
        }
        var result = Self.zero
        for (degree, coefficient) in try orderedTerms(usage: &usage) {
            let a = try power(u, degree.u, usage: &usage)
            let b = try power(v, degree.v, usage: &usage)
            result = try result.adding(a.multiplied(by: b, usage: &usage)
                .scaled(by: coefficient, usage: &usage), usage: &usage)
        }
        return result
    }
}
