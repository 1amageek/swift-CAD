#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public protocol OriginalCompleteCurveGraphPreparing: Sendable {
    associatedtype Source: Sendable
    associatedtype Evidence: Sendable
    associatedtype Coverage: Sendable
    func prepare<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        field: OriginalExactScalarDomain,maximumCharts: Int,limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalCompleteCurveGraphs<Source,Evidence,Coverage>
}
