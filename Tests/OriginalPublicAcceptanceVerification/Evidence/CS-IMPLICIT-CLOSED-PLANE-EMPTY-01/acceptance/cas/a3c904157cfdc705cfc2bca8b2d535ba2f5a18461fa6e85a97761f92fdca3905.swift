/// Preserves the existing identity-transport, auxiliary-free curve capability.
struct OriginalIdentityRationalGraphCurvePointEvaluator<S: Sendable,E: Sendable>: OriginalRationalGraphCurvePointEvaluating {
    typealias Source = S
    typealias Evidence = E
    func admit<A: ExactScalarAdmission & ~Copyable>(
        _ graph: OriginalParametricGraphReceipt<S,OriginalExactScalarDomain,E>,
        limits: OriginalDomainIdentityLimits, using admission: inout A) throws {
        try OriginalRationalGraphPointAccess.requireIdentity(graph, arity: 1, using: &admission)
    }
    func validate<A: ExactScalarAdmission & ~Copyable>(_ point: OriginalIssuedExactIntersectionPoint,
        graph: OriginalParametricGraphReceipt<S,OriginalExactScalarDomain,E>,
        limits: OriginalDomainIdentityLimits, using admission: inout A) throws {}
    func tangent<A: ExactScalarAdmission & ~Copyable>(
        _ graph: OriginalParametricGraphReceipt<S,OriginalExactScalarDomain,E>,
        at parameters: [ExactAlgebraicScalar<OriginalExactScalarDomain>],
        field: ExactAlgebraicScalarDomain<OriginalExactScalarDomain>, using admission: inout A
    ) throws -> [ExactAlgebraicScalar<OriginalExactScalarDomain>] {
        try OriginalRationalGraphPointAccess.derivative(graph, at: parameters, axis: 0, field: field, using: &admission)
    }
    func position<A: ExactScalarAdmission & ~Copyable>(
        _ graph: OriginalParametricGraphReceipt<S,OriginalExactScalarDomain,E>, numbers: [Double],
        field: OriginalExactScalarDomain, limits: OriginalDomainIdentityLimits, using admission: inout A
    ) throws -> [OriginalExactScalar]? {
        try OriginalRationalGraphPointAccess.position(graph, numbers: numbers, offset: 0, field: field,
            limits: limits, using: &admission)
    }
}
