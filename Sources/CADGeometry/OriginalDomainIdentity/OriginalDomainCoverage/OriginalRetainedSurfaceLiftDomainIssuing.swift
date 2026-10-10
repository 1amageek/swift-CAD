#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public protocol OriginalRetainedSurfaceLiftDomainIssuing: Sendable {
    associatedtype Source: OriginalLiftGraphSourceReading
    func frame<A: ExactScalarAdmission & ~Copyable>(family: borrowing OriginalFiniteRetainedSurfaceLiftGraphs<Source>,
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalParameterFrame<Source,OriginalExactScalarDomain>
    func issue<A: ExactScalarAdmission & ~Copyable>(request: borrowing OriginalParameterSelection<Source,OriginalExactScalarDomain>,
        family: borrowing OriginalFiniteRetainedSurfaceLiftGraphs<Source>,limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalRetainedSurfaceLiftDomainCover<Source>
}
