#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Complete fundamental templates, with separate all-integer source period authority.
public struct OriginalBSplineFundamentalCharts<S: OriginalBSplineSourceReading>: Sendable {
    public let source: OriginalSourceBinding<S>
    public let field: OriginalExactScalarDomain
    public let support: [OriginalSourceParameterInterval<OriginalExactScalar>]
    public let laws: [OriginalRationalChartReceipt<S,OriginalBSplineChartSelection,OriginalExactScalarDomain>]
    public let periods: [OriginalSourcePeriodReceipt<S,OriginalExactScalarDomain>]
    init(source: OriginalSourceBinding<S>,field: OriginalExactScalarDomain,
        support: [OriginalSourceParameterInterval<OriginalExactScalar>],
        laws: [OriginalRationalChartReceipt<S,OriginalBSplineChartSelection,OriginalExactScalarDomain>],
        periods: [OriginalSourcePeriodReceipt<S,OriginalExactScalarDomain>]) {
        self.source=source;self.field=field;self.support=support;self.laws=laws;self.periods=periods
    }
}
