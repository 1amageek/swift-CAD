#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public protocol OriginalBSplineDomainIssuing: Sendable {
    associatedtype Source: OriginalBSplineSourceReading
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering
    func prepare<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,field: Field,
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalBSplineDomainSpace<Source,Field>
    func issue<A: ExactScalarAdmission & ~Copyable>(space: borrowing OriginalBSplineDomainSpace<Source,Field>,
        request: borrowing OriginalParameterSelection<Source,Field>,limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalBSplineDomainCover<Source,Field>
}
