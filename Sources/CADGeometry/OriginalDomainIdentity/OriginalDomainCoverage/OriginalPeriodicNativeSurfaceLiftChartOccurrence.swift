#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Original T/UV relation and unreduced surface cycles retain their proof owners.
public struct OriginalPeriodicNativeSurfaceLiftChartOccurrence<S: OriginalSurfaceLiftSourceReading>: Sendable {
    public let family: OriginalPeriodicNativeSurfaceLiftGraphs<S>
    public let template: Int
    public let cycles: [OriginalParameterCycle]
    public let relation: OriginalDomainBoundParametricGraph<S,OriginalExactScalarDomain,OriginalSurfaceLiftGraphEvidence<S>>
    init(family: OriginalPeriodicNativeSurfaceLiftGraphs<S>,template: Int,cycles: [OriginalParameterCycle],
        relation: OriginalDomainBoundParametricGraph<S,OriginalExactScalarDomain,OriginalSurfaceLiftGraphEvidence<S>>) {
        self.family=family;self.template=template;self.cycles=cycles;self.relation=relation
    }
}
