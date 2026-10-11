/// Exact material refinement over the retained lifted graph, preserving all witnesses.
public protocol OriginalIssuedGraphBoundaryClipping: Sendable {
    associatedtype First: Sendable
    associatedtype FirstEvidence: Sendable
    associatedtype FirstCover: Sendable
    associatedtype Second: Sendable
    associatedtype SecondEvidence: Sendable
    associatedtype SecondCover: Sendable
    func clip<A: ExactScalarAdmission & ~Copyable>(
        _ boundary: OriginalIssuedGraphBoundaryDomain<First, FirstEvidence, FirstCover, Second, SecondEvidence, SecondCover>,
        selection: OriginalNativeBoundaryDomain.Selection, domainLimits: OriginalDomainIdentityLimits,
        cellLimits: ExactRealCellLimits, topologyLimits: ExactRealTopologyLimits, using admission: inout A
    ) throws(NativeExactRelationFailure) -> OriginalIssuedGraphClippedParameters<First, FirstEvidence, FirstCover, Second, SecondEvidence, SecondCover>
}
