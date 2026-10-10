#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public protocol OriginalPeriodicNativeSurfaceLiftDomainIssuing: Sendable {
    associatedtype Source: OriginalLiftSourceReading
    func prepare<A: ExactScalarAdmission & ~Copyable>(family: borrowing OriginalPeriodicNativeSurfaceLiftGraphs<Source>,
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalPeriodicNativeSurfaceLiftDomainSpace<Source>
    func issue<A: ExactScalarAdmission & ~Copyable>(space: borrowing OriginalPeriodicNativeSurfaceLiftDomainSpace<Source>,
        request: borrowing OriginalParameterSelection<Source,OriginalExactScalarDomain>,
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalPeriodicNativeSurfaceLiftDomainCover<Source>
}
