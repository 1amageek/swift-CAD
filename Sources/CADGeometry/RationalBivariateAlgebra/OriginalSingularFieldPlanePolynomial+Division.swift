extension OriginalSingularFieldPlanePolynomial {
    package func exchangedAxes<B: RationalAlgebraAdmitting>(maximumDepth: Int, usage: inout B) throws -> Self {
        var values: [ExactBivariatePolynomial.Power: OriginalSingularFieldElement] = [:]
        try RationalAlgebraStorage.retain(coefficients.count, of: (ExactBivariatePolynomial.Power, OriginalSingularFieldElement).self, usage: &usage)
        for (power, value) in try orderedTerms(usage: &usage) { values[try .init(u: power.v, v: power.u)] = value }
        return try Self(context: context, coefficients: values, maximumDepth: maximumDepth, usage: &usage)
    }
    package func leading<B: RationalAlgebraAdmitting>(usage: inout B)
        throws -> (key: ExactBivariatePolynomial.Power, value: OriginalSingularFieldElement)? {
        try orderedTerms(usage: &usage).max { a, b in a.key.v == b.key.v ? a.key.u < b.key.u : a.key.v < b.key.v }
    }
    package var uDegree: Int { coefficients.keys.reduce(-1) { max($0, $1.u) } }
    package var vDegree: Int { coefficients.keys.reduce(-1) { max($0, $1.v) } }
    package static func monomial<B: RationalAlgebraAdmitting>(u: Int, v: Int,
        coefficient: OriginalSingularFieldElement, maximumDepth: Int, usage: inout B) throws -> Self {
        try Self(context: coefficient.context, coefficients: [.init(u: u, v: v): coefficient],
            maximumDepth: maximumDepth, usage: &usage)
    }
    package func normalized<B: RationalAlgebraAdmitting>(maximumDepth: Int, usage: inout B) throws -> Self {
        guard let lead = try leading(usage: &usage) else { return self }
        var values: [ExactBivariatePolynomial.Power: OriginalSingularFieldElement] = [:]
        try RationalAlgebraStorage.retain(coefficients.count, of: (ExactBivariatePolynomial.Power, OriginalSingularFieldElement).self, usage: &usage)
        for (power, value) in try orderedTerms(usage: &usage) {
            values[power] = try value.divided(by: lead.value, maximumDepth: maximumDepth, usage: &usage)
        }
        return try Self(context: context, coefficients: values, maximumDepth: maximumDepth, usage: &usage)
    }
    package func subtracting<B: RationalAlgebraAdmitting>(_ other: Self,
        maximumDepth: Int, usage: inout B) throws -> Self {
        var values: [ExactBivariatePolynomial.Power: OriginalSingularFieldElement] = [:]
        try RationalAlgebraStorage.retain(other.coefficients.count, of: (ExactBivariatePolynomial.Power, OriginalSingularFieldElement).self, usage: &usage)
        for (power, value) in try other.orderedTerms(usage: &usage) {
            values[power] = try value.negated(maximumDepth: maximumDepth, usage: &usage)
        }
        return try adding(Self(context: other.context, coefficients: values, maximumDepth: maximumDepth, usage: &usage),
            maximumDepth: maximumDepth, usage: &usage)
    }
}
