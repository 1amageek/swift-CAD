#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Whole original Native support and a finite fundamental template cover.
public struct OriginalBSplineDomainSpace<S: OriginalBSplineSourceReading,F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    public let frame: OriginalParameterFrame<S,F>
    public let fundamental: OriginalDomainCover<S,F>
    public let periods: [OriginalSourcePeriodReceipt<S,F>]
    public let sourceCharts: [OriginalSourceChart<S,OriginalBSplineChartSelection>]
    public var source: OriginalSourceBinding<S> { frame.source }
    init(frame: OriginalParameterFrame<S,F>,fundamental: OriginalDomainCover<S,F>,
        periods: [OriginalSourcePeriodReceipt<S,F>],sourceCharts: [OriginalSourceChart<S,OriginalBSplineChartSelection>]) {
        self.frame = frame; self.fundamental = fundamental; self.periods = periods; self.sourceCharts = sourceCharts
    }
}
