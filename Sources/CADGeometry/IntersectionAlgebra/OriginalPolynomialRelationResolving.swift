/// Complete real coverage of one original relation; partial publication is forbidden.
public protocol OriginalPolynomialRelationResolving: Sendable {
    func decompose(_ relation: OriginalPolynomialRelation, maximumDepth: Int,
        maximumCoefficientDepth: Int, usage: OriginalRelationUsage) throws -> OriginalRealRelation
}
