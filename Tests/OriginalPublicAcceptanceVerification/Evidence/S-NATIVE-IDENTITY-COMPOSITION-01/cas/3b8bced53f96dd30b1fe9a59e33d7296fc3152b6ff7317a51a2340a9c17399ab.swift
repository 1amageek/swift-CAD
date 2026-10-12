#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public protocol OriginalIntrinsicSphereDomainIssuing: Sendable {
    associatedtype Source: OriginalIntrinsicSphereSourceReading
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering
    func frame<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,field: Field,
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterFrame<Source,Field>
    func issue<A: ExactScalarAdmission & ~Copyable>(request: borrowing OriginalParameterSelection<Source,Field>,limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalIntrinsicSphereDomainCover<Source,Field>
}
