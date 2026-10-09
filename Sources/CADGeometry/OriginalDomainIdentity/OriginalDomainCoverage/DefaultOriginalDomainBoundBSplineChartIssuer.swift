#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public struct DefaultOriginalDomainBoundBSplineChartIssuer<S: OriginalBSplineSourceReading,F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: OriginalDomainBoundRationalChartIssuing {
    public typealias Source = S
    public typealias Field = F
    public init() {}
    public func issue<A: ExactScalarAdmission & ~Copyable>(cover: borrowing OriginalBSplineDomainCover<S,F>,template: Int,
        cycles: borrowing [OriginalParameterCycle],limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalDomainBoundRationalChart<S,F> {
        try issue(cover:cover,template:template,cycles:cycles,sourceIssuer:DefaultOriginalBSplineChartIssuer<S,F>(),
            transporter:DefaultOriginalParameterTransporter<S,F>(),limits:limits,using:&admission)
    }
    public func issue<I: OriginalRationalChartIssuing,T: OriginalParameterTransporting,A: ExactScalarAdmission & ~Copyable>(
        cover: borrowing OriginalBSplineDomainCover<S,F>,template: Int,cycles: borrowing [OriginalParameterCycle],
        sourceIssuer: I,transporter: T,limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalDomainBoundRationalChart<S,F>
        where I.Source == S,I.Field == F,I.Selection == OriginalBSplineChartSelection,T.Source == S,T.Field == F {
        let cover = copy cover,cycles = copy cycles
        return try OriginalDomainAccess.run(&admission) { a in
            let member = try cover.member(template:template,cycles:cycles,limits:limits,using:&a)
            let law = try sourceIssuer.issue(source:cover.space.source,chart:member.sourceChart,
                field:cover.space.frame.scalarField,limits:limits.source,using:&a)
            guard cover.source.owns(law.chart) else { throw OriginalDomainIdentityFailure.foreignOwner }
            guard law.chart.selection.spans == member.sourceChart.selection.spans else {
                throw OriginalDomainIdentityFailure.invalidDomain
            }
            guard law.support.count == member.correspondence.local.arity else { throw OriginalDomainIdentityFailure.invalidDomain }
            let fullInverse = try transporter.inverse(member.correspondence,limits:limits,using:&a)
            let inverse = try transporter.restrict(fullInverse,to:member.selectedImage,limits:limits,using:&a)
            // Both consumers share the same source/law/transport owners. No roots,
            // normal fields, solver replay or homogeneous coefficient copy is introduced.
            return .init(law:law,occurrence:member,localSelection:inverse.image,inverse:inverse)
        }
    }
}
