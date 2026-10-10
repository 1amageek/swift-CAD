#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public protocol OriginalPeriodicNativeSurfaceLiftDomainQuerying: Sendable {
    associatedtype Source: OriginalLiftSourceReading
    var source: OriginalSourceBinding<Source> { get }
    var enclosingSupport: OriginalParameterSelection<Source,OriginalExactScalarDomain> { get }
    var request: OriginalParameterSelection<Source,OriginalExactScalarDomain> { get }
    var effectiveEnclosure: OriginalParameterSelection<Source,OriginalExactScalarDomain> { get }
    var templateCount: Int { get }
    var surfaceCycleRank: Int { get }
    func member<A: ExactScalarAdmission & ~Copyable>(template: Int,cycles: borrowing [OriginalParameterCycle],
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalPeriodicNativeSurfaceLiftChartOccurrence<Source>
    func liftedPositionIncidents<A: ExactScalarAdmission & ~Copyable>(at tuple: borrowing [OriginalExactScalar],
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> [OriginalPeriodicNativeSurfaceLiftChartOccurrence<Source>]
}
