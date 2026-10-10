#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public protocol OriginalBSplineFundamentalChartPreparing: Sendable {
    associatedtype Source: OriginalBSplineSourceReading
    func prepare<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        field: borrowing OriginalExactScalarDomain,maximumCharts: Int,limits: OriginalSourceIssuanceLimits,
        using admission: inout A) throws(OriginalSourceIssuanceFailure) -> OriginalBSplineFundamentalCharts<Source>
}
