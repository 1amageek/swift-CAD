#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public protocol OriginalFiniteNativeRollingBallGraphPreparing: Sendable {
    associatedtype Source: OriginalRollingBallSourceReading
    func prepare<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        center: borrowing OriginalFiniteBSplineCharts<Source.Child>,
        first: borrowing OriginalFiniteBSplineCharts<Source.Child>,
        second: borrowing OriginalFiniteBSplineCharts<Source.Child>, maximumCharts: Int,
        limits: OriginalSourceIssuanceLimits, using a: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalFiniteNativeRollingBallGraphs<Source>
}
