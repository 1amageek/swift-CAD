#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public struct DefaultOriginalBSplineFundamentalChartPreparer<S: OriginalBSplineSourceReading>: OriginalBSplineFundamentalChartPreparing {
    public typealias Source=S
    public init() {}
    public func prepare<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<S>,
        field: borrowing OriginalExactScalarDomain,maximumCharts: Int,limits: OriginalSourceIssuanceLimits,
        using admission: inout A) throws(OriginalSourceIssuanceFailure) -> OriginalBSplineFundamentalCharts<S> {
        do {
            let values=try DefaultOriginalFiniteBSplineChartPreparer<S>().build(source:source,field:field,
                maximumCharts:maximumCharts,periodic:true,limits:limits,using:&admission)
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalBSplineFundamentalCharts<S>.self))
            let result=OriginalBSplineFundamentalCharts(source:copy source,field:copy field,support:values.0,laws:values.1,periods:values.2)
            try admission.checkpoint();return result
        } catch { throw .init(preserving:error) }
    }
}
