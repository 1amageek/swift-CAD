#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public protocol OriginalPlaneDomainIssuing: Sendable {
    associatedtype Source: OriginalPlaneSourceReading
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering
    func frame<A: ExactScalarAdmission & ~Copyable>(basis: borrowing OriginalPlaneBasisReceipt<Source,Field>,
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterFrame<Source,Field>
    func issue<A: ExactScalarAdmission & ~Copyable>(request: borrowing OriginalParameterSelection<Source,Field>,
        basis: borrowing OriginalPlaneBasisReceipt<Source,Field>,limits: OriginalDomainIdentityLimits,using admission: inout A
    ) throws(OriginalDomainIdentityFailure) -> OriginalPrimitiveDomainCover<Source,Field,OriginalPlaneBasisReceipt<Source,Field>>
}
