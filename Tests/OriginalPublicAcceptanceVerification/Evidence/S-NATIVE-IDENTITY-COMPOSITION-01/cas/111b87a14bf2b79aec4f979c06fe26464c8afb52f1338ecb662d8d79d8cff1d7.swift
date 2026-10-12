#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public protocol OriginalDomainBoundRationalChartIssuing: Sendable {
    associatedtype Source: OriginalBSplineSourceReading
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting
    func issue<A: ExactScalarAdmission & ~Copyable>(cover: borrowing OriginalBSplineDomainCover<Source,Field>,template: Int,
        cycles: borrowing [OriginalParameterCycle],limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalDomainBoundRationalChart<Source,Field>
}
