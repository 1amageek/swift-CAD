#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
#endif

public protocol OriginalFiniteRetainedSurfaceChartPreparing {
    associatedtype Source:OriginalRetainedSurfaceSourceReading
    func prepare<A:ExactScalarAdmission & ~Copyable>(source:borrowing OriginalSourceBinding<Source>,
        maximumCharts:Int,limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure)
        -> OriginalFiniteRetainedSurfaceCharts<Source>
}
