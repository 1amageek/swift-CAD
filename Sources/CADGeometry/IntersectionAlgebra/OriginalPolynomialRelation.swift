/// One original rational relation and its exact coordinate domains.
public struct OriginalPolynomialRelation: Sendable {
    public let variableCount: Int
    public let polynomials: [OriginalRationalPolynomial]
    public let predicate: OriginalPolynomialPredicate
    public let domains: [OriginalRationalParameterDomain]

    public init<B: RationalAlgebraAdmitting>(variableCount: Int,
        polynomials: [OriginalRationalPolynomial], predicate: OriginalPolynomialPredicate,
        domains: [OriginalRationalParameterDomain], usage: inout B) throws {
        try intersectionAlgebraStep(&usage)
        guard (1...4).contains(variableCount), domains.count == variableCount,
            predicate.polynomialCount == polynomials.count else {
            throw rationalAlgebraFailure("An original relation requires its complete ring, domain and predicate binding.")
        }
        for polynomial in polynomials {
            try intersectionAlgebraStep(&usage)
            guard polynomial.variableCount == variableCount else {
                throw rationalAlgebraFailure("An original relation cannot combine different coordinate rings.")
            }
        }
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        self.variableCount = variableCount; self.polynomials = polynomials
        self.predicate = predicate; self.domains = domains
    }
}
