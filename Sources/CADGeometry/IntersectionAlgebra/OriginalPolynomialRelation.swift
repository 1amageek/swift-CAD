/// One original rational or ordered relation and its exact geometric domains.
public struct OriginalPolynomialRelation: Sendable {
    public enum Polynomials: Sendable {
        case rational([OriginalRationalPolynomial])
        case ordered([OriginalOrderedPolynomial])
        public var count: Int {
            switch self { case .rational(let laws): laws.count; case .ordered(let laws): laws.count }
        }
    }
    public let variableCount: Int
    public let polynomials: Polynomials
    public let predicate: OriginalPolynomialPredicate
    public let domains: [OriginalRationalParameterDomain]

    public init<B: RationalAlgebraAdmitting>(variableCount: Int,
        polynomials: [OriginalRationalPolynomial], predicate: OriginalPolynomialPredicate,
        domains: [OriginalRationalParameterDomain], usage: inout B) throws {
        try self.init(variableCount: variableCount, polynomials: .rational(polynomials),
            predicate: predicate, domains: domains, usage: &usage)
    }

    public init<B: RationalAlgebraAdmitting>(variableCount: Int,
        orderedPolynomials: [OriginalOrderedPolynomial], predicate: OriginalPolynomialPredicate,
        domains: [OriginalRationalParameterDomain], usage: inout B) throws {
        try self.init(variableCount: variableCount, polynomials: .ordered(orderedPolynomials),
            predicate: predicate, domains: domains, usage: &usage)
    }

    private init<B: RationalAlgebraAdmitting>(variableCount: Int, polynomials: Polynomials,
        predicate: OriginalPolynomialPredicate, domains: [OriginalRationalParameterDomain], usage: inout B) throws {
        try intersectionAlgebraStep(&usage)
        guard (1...4).contains(variableCount), domains.count == variableCount,
            predicate.polynomialCount == polynomials.count else {
            throw rationalAlgebraFailure("An original relation requires its complete ring, domain and predicate binding.")
        }
        switch polynomials {
        case .rational(let laws):
            for law in laws {
                try intersectionAlgebraStep(&usage)
                guard law.variableCount == variableCount else {
                    throw rationalAlgebraFailure("An original relation cannot combine different coordinate rings.")
                }
            }
        case .ordered(let laws):
            for law in laws {
                try intersectionAlgebraStep(&usage)
                guard law.variableCount == variableCount else {
                    throw rationalAlgebraFailure("An ordered relation cannot combine different geometric coordinate rings.")
                }
            }
        }
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        self.variableCount = variableCount; self.polynomials = polynomials
        self.predicate = predicate; self.domains = domains
    }
}
