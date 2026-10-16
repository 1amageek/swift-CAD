/// Complete real coverage of one original relation; partial publication is forbidden.
public protocol OriginalPolynomialRelationResolving: Sendable {
    func decompose<A: ExactScalarAdmission & ~Copyable>(_ relation: OriginalPolynomialRelation, maximumDepth: Int,
        maximumCoefficientDepth: Int, usage: inout A) throws -> OriginalRealRelation
}
