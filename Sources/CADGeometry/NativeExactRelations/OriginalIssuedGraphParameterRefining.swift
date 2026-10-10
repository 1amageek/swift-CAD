#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION
import L0
import L3
import L4
import DI
#endif

/// Refines a retained lifted relation without resolving its intersection again.
public protocol OriginalIssuedGraphParameterRefining: Sendable {
    associatedtype First: Sendable
    associatedtype FirstEvidence: Sendable
    associatedtype FirstCover: Sendable
    associatedtype Second: Sendable
    associatedtype SecondEvidence: Sendable
    associatedtype SecondCover: Sendable
    func refine<A: ExactScalarAdmission & ~Copyable>(
        in raw: borrowing OriginalIssuedGraphRelations<First,FirstEvidence,FirstCover,Second,SecondEvidence,SecondCover>,
        pairOrdinal: Int, matching predicate: borrowing ExactRealCellPredicate<OriginalExactScalarDomain>,
        limits: OriginalDomainIdentityLimits, cellLimits: ExactRealCellLimits,
        topologyLimits: ExactRealTopologyLimits, using admission: inout A
    ) throws(NativeExactRelationFailure) -> OriginalIssuedGraphParameterRefinement<First,FirstEvidence,FirstCover,Second,SecondEvidence,SecondCover>
}
