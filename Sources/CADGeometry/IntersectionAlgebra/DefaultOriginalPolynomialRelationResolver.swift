/// Original sign-invariant real decomposition, closure and component composition.
public struct DefaultOriginalPolynomialRelationResolver: OriginalPolynomialRelationResolving {
    public init() {}

    public func decompose<A: ExactScalarAdmission & ~Copyable>(_ relation: OriginalPolynomialRelation, maximumDepth: Int,
        maximumCoefficientDepth: Int, usage: inout A) throws -> OriginalRealRelation {
        do {
            return try decomposeOriginal(relation, maximumDepth: maximumDepth,
                maximumCoefficientDepth: maximumCoefficientDepth, usage: &usage)
        } catch let failure as ExactScalarFailure {
            throw OriginalQueryFailure.published(failure,context:.unspecified,tolerance:nil)
        }
    }

    private func decomposeOriginal<A: ExactScalarAdmission & ~Copyable>(_ relation: OriginalPolynomialRelation, maximumDepth: Int,
        maximumCoefficientDepth: Int, usage: inout A) throws -> OriginalRealRelation {
        guard maximumDepth>=0,(0...32).contains(maximumCoefficientDepth) else {
            throw rationalAlgebraFailure("Original relation requires independent valid caller depth limits.")
        }
        return try usage.withProofScope(maximum:try .init(value:maximumDepth,coefficient:maximumCoefficientDepth)) { admission in
        try intersectionAlgebraStep(&admission)
        let selected: OriginalRationalIntersectionCells
        let ordered: OriginalOrderedIntersectionCells?
        switch relation.polynomials {
        case .rational(let polynomials):
            try RationalAlgebraStorage.retain(polynomials.count, of: ExactIntersectionPolynomial.self, usage: &admission)
            var laws: [ExactIntersectionPolynomial] = []; laws.reserveCapacity(polynomials.count)
            for polynomial in polynomials {
                try intersectionAlgebraStep(&admission); laws.append(polynomial.original)
            }
            let ambient = try OriginalRationalIntersectionCells.prepare(equations: [],
                variableCount: relation.variableCount, exactDomains: relation.domains,
                partitionPolynomials: laws, thomEncoding: true, maximumDepth: maximumDepth, usage: &admission)
            selected = try ambient.selecting(relation.predicate.original, usage: &admission); ordered = nil
        case .ordered(let polynomials):
            try RationalAlgebraStorage.retain(polynomials.count, of: OriginalOrderedIntersectionPolynomial.self, usage: &admission)
            var laws: [OriginalOrderedIntersectionPolynomial] = []; laws.reserveCapacity(polynomials.count)
            for polynomial in polynomials { try intersectionAlgebraStep(&admission); laws.append(polynomial.original) }
            let issued = try OriginalOrderedIntersectionCells.prepare(polynomials: laws,
                predicate: relation.predicate.original, variableCount: relation.variableCount, domains: relation.domains,
                maximumDepth: maximumDepth, maximumCoefficientDepth: maximumCoefficientDepth, usage: &admission)
            selected = issued.partition; ordered = issued
        }
        let incidence = try OriginalRationalIntersectionIncidence.prepare(partition: selected,
            maximumDepth: maximumDepth, usage: &admission)
        return try OriginalRealRelation(original: relation, ordered: ordered, incidence: incidence,
            components: incidence.connectedComponents(usage: &admission), maximumDepth: maximumDepth, usage: &admission)
        }
    }
}
