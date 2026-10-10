#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// The three original local laws are retained, including every one-sided owner.
public struct OriginalRollingBallGraphEvidence<S: OriginalRollingBallSourceReading>: Sendable {
    public let center: OriginalRationalChartReceipt<S.Child, OriginalBSplineChartSelection, OriginalExactScalarDomain>
    public let first: OriginalRationalChartReceipt<S.Child, OriginalBSplineChartSelection, OriginalExactScalarDomain>
    public let second: OriginalRationalChartReceipt<S.Child, OriginalBSplineChartSelection, OriginalExactScalarDomain>
    init(center: OriginalRationalChartReceipt<S.Child, OriginalBSplineChartSelection, OriginalExactScalarDomain>,
        first: OriginalRationalChartReceipt<S.Child, OriginalBSplineChartSelection, OriginalExactScalarDomain>,
        second: OriginalRationalChartReceipt<S.Child, OriginalBSplineChartSelection, OriginalExactScalarDomain>) {
        self.center = center; self.first = first; self.second = second
    }
}
