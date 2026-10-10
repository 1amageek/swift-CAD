#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public protocol OriginalRollingBallGraphDomainIssuing: Sendable {
    associatedtype Source: OriginalRollingBallChildSourceReading
    associatedtype ChildEvidence: Sendable
    associatedtype ChildCoverage: Sendable
    func frame<A: ExactScalarAdmission & ~Copyable>(family: borrowing OriginalFiniteRollingBallGraphs<Source,ChildEvidence,ChildCoverage>,
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalParameterFrame<Source,OriginalExactScalarDomain>
    func issue<A: ExactScalarAdmission & ~Copyable>(request: borrowing OriginalParameterSelection<Source,OriginalExactScalarDomain>,
        family: borrowing OriginalFiniteRollingBallGraphs<Source,ChildEvidence,ChildCoverage>,limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalRollingBallGraphDomainCover<Source,ChildEvidence,ChildCoverage>
}
