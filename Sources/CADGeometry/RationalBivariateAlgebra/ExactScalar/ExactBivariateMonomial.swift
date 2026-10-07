public extension ExactBivariatePolynomial {
    static func monomial<B: RationalAlgebraAdmitting>(u: Int, v: Int,
        coefficient: ExactRationalCoefficient, usage: inout B) throws -> Self {
        let power = try Power(u: u, v: v)
        if coefficient.isZero { return .zero }
        try usage.consumeExactWork(1)
        try RationalAlgebraStorage.retain(1, of: (Power, ExactRationalCoefficient).self, usage: &usage)
        return Self([power: coefficient])
    }

    func exchangedAxes<B: RationalAlgebraAdmitting>(usage: inout B) throws -> Self {
        try RationalAlgebraStorage.retain(coefficients.count, of: (Power, ExactRationalCoefficient).self, usage: &usage)
        var result: [Power: ExactRationalCoefficient] = [:]
        for term in try orderedTerms(usage: &usage) {
            result[try Power(u: term.key.v, v: term.key.u)] = term.value
        }
        return Self(result)
    }
}
