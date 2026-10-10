#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public protocol OriginalPeriodicNativeOffsetDomainIssuing: Sendable {
    associatedtype Source: OriginalOffsetSourceReading where Source.Child: OriginalBSplineSourceReading
    func prepare<A: ExactScalarAdmission & ~Copyable>(family: borrowing OriginalPeriodicNativeOffsetLawFamily<Source>,
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalPeriodicNativeOffsetDomainSpace<Source>
    func issue<A: ExactScalarAdmission & ~Copyable>(space: borrowing OriginalPeriodicNativeOffsetDomainSpace<Source>,
        request: borrowing OriginalParameterSelection<Source,OriginalExactScalarDomain>,
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalPeriodicNativeOffsetDomainCover<Source>
}
