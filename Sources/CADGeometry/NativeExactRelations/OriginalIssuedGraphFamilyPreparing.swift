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

public protocol OriginalIssuedGraphFamilyPreparing: Sendable {
    associatedtype Source: Sendable
    associatedtype Evidence: Sendable
    associatedtype Cover: Sendable
    func prepare<A: ExactScalarAdmission & ~Copyable>(cover: borrowing Cover,field: borrowing ExactAlgebraicScalarDomain<OriginalExactScalarDomain>,
        maximumGraphs:Int,limits:OriginalDomainIdentityLimits,using admission:inout A)
        throws(NativeExactRelationFailure) -> OriginalIssuedGraphFamily<Source,Evidence,Cover>
}
