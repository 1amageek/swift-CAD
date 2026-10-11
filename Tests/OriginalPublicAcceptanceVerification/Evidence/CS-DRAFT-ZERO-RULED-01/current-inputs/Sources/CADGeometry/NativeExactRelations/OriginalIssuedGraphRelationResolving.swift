#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import DI
import SourceIssuer
#endif

public protocol OriginalIssuedGraphRelationResolving: Sendable {
    associatedtype First: Sendable
    associatedtype FirstEvidence: Sendable
    associatedtype FirstCover: Sendable
    associatedtype Second: Sendable
    associatedtype SecondEvidence: Sendable
    associatedtype SecondCover: Sendable
    func resolve<A: ExactScalarAdmission & ~Copyable>(kind:ExactParametricRelationKind,
        first:borrowing OriginalIssuedGraphFamily<First,FirstEvidence,FirstCover>,second:borrowing OriginalIssuedGraphFamily<Second,SecondEvidence,SecondCover>,
        maximumPairs:Int,limits:OriginalDomainIdentityLimits,cellLimits:ExactRealCellLimits,topologyLimits:ExactRealTopologyLimits,using admission:inout A)
        throws(NativeExactRelationFailure) -> OriginalIssuedGraphRelations<First,FirstEvidence,FirstCover,Second,SecondEvidence,SecondCover>
}
