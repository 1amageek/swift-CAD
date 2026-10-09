#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Authoritative native support and all span laws share the original binding owner.
public struct OriginalFiniteBSplineCharts<Source: OriginalBSplineSourceReading>: Sendable {
    public let source: OriginalSourceBinding<Source>
    public let field: OriginalExactScalarDomain
    public let support: [OriginalSourceParameterInterval<OriginalExactScalar>]
    public let laws: [OriginalRationalChartReceipt<Source, OriginalBSplineChartSelection, OriginalExactScalarDomain>]
    init(source: OriginalSourceBinding<Source>, field: OriginalExactScalarDomain,
        support: [OriginalSourceParameterInterval<OriginalExactScalar>],
        laws: [OriginalRationalChartReceipt<Source, OriginalBSplineChartSelection, OriginalExactScalarDomain>]) {
        self.source = source; self.field = field; self.support = support; self.laws = laws
    }
}
