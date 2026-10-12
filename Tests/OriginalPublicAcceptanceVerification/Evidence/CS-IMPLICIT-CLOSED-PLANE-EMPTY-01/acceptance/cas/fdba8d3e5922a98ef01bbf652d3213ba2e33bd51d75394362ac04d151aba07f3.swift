/// Source-authorized first-curve evaluation for shared numerical publication.
protocol OriginalRationalGraphCurvePointEvaluating: Sendable {
    associatedtype Source: Sendable
    associatedtype Evidence: Sendable
    func admit<A: ExactScalarAdmission & ~Copyable>(
        _ graph: OriginalParametricGraphReceipt<Source,OriginalExactScalarDomain,Evidence>,
        limits: OriginalDomainIdentityLimits, using admission: inout A) throws
    func validate<A: ExactScalarAdmission & ~Copyable>(_ point: OriginalIssuedExactIntersectionPoint,
        graph: OriginalParametricGraphReceipt<Source,OriginalExactScalarDomain,Evidence>,
        limits: OriginalDomainIdentityLimits, using admission: inout A) throws
    func tangent<A: ExactScalarAdmission & ~Copyable>(
        _ graph: OriginalParametricGraphReceipt<Source,OriginalExactScalarDomain,Evidence>,
        at parameters: [ExactAlgebraicScalar<OriginalExactScalarDomain>],
        field: ExactAlgebraicScalarDomain<OriginalExactScalarDomain>, using admission: inout A
    ) throws -> [ExactAlgebraicScalar<OriginalExactScalarDomain>]
    func position<A: ExactScalarAdmission & ~Copyable>(
        _ graph: OriginalParametricGraphReceipt<Source,OriginalExactScalarDomain,Evidence>,
        numbers: [Double], field: OriginalExactScalarDomain, limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws -> [OriginalExactScalar]?
}
