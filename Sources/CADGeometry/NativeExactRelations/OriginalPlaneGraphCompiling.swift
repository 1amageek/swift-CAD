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

public protocol OriginalPlaneGraphCompiling: Sendable {
    associatedtype Source: OriginalPlaneSourceReading
    func compile<A: ExactScalarAdmission & ~Copyable>(
        cover: borrowing OriginalPrimitiveDomainCover<Source,OriginalExactScalarDomain,OriginalPlaneBasisReceipt<Source,OriginalExactScalarDomain>>,
        field: borrowing ExactAlgebraicScalarDomain<OriginalExactScalarDomain>,
        limits: OriginalDomainIdentityLimits, using admission: inout A
    ) throws(NativeExactRelationFailure) -> OriginalIssuedPlaneGraph<Source>
}
