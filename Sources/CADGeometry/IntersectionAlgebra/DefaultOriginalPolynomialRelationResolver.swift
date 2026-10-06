/// Original sign-invariant real decomposition, closure and component composition.
public struct DefaultOriginalPolynomialRelationResolver: OriginalPolynomialRelationResolving {
    public init() {}

    public func decompose(_ relation: OriginalPolynomialRelation, maximumDepth: Int,
        usage: OriginalRelationUsage) throws -> OriginalRealRelation {
        var admission = usage
        try intersectionAlgebraStep(&admission)
        try RationalAlgebraStorage.retain(relation.polynomials.count, of: ExactIntersectionPolynomial.self, usage: &admission)
        var laws: [ExactIntersectionPolynomial] = []; laws.reserveCapacity(relation.polynomials.count)
        for polynomial in relation.polynomials {
            try intersectionAlgebraStep(&admission); laws.append(polynomial.original)
        }
        let ambient = try OriginalRationalIntersectionCells.prepare(equations: [],
            variableCount: relation.variableCount, exactDomains: relation.domains,
            partitionPolynomials: laws, thomEncoding: true, maximumDepth: maximumDepth, usage: &admission)
        let selected = try ambient.selecting(relation.predicate.original, usage: &admission)
        let incidence = try OriginalRationalIntersectionIncidence.prepare(partition: selected,
            maximumDepth: maximumDepth, usage: &admission)
        return try OriginalRealRelation(original: relation, incidence: incidence,
            components: incidence.connectedComponents(usage: &admission), usage: &admission)
    }
}
