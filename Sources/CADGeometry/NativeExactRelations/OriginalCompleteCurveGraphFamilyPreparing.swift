/// Composes sealed complete curve coverage with a checked original T request.
public protocol OriginalCompleteCurveGraphFamilyPreparing: Sendable {
    associatedtype Source: Sendable
    associatedtype Evidence: Sendable
    associatedtype Coverage: Sendable
    func prepare<A: ExactScalarAdmission & ~Copyable>(
        family: borrowing OriginalCompleteCurveGraphs<Source,Evidence,Coverage>,
        request: borrowing OriginalParameterSelection<Source,OriginalExactScalarDomain>,
        field: borrowing ExactAlgebraicScalarDomain<OriginalExactScalarDomain>,
        maximumGraphs: Int, limits: OriginalDomainIdentityLimits, using admission: inout A
    ) throws(NativeExactRelationFailure) -> OriginalIssuedGraphFamily<Source,Evidence,
        OriginalCompleteCurveGraphDomainCover<Source,Evidence,Coverage>>
}
