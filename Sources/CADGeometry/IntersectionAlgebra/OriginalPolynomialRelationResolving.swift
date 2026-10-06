/// Complete real coverage of one rational relation; partial publication is forbidden.
public protocol OriginalPolynomialRelationResolving: Sendable {
    func decompose(_ relation: OriginalPolynomialRelation, maximumDepth: Int,
        usage: OriginalRelationUsage) throws -> OriginalRealRelation
}
