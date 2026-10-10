#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public protocol OriginalPeriodicNativeSurfaceLiftGraphPreparing: Sendable {
    associatedtype Source: OriginalSurfaceLiftSourceReading
    func prepare<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        surface: borrowing OriginalBSplineFundamentalCharts<Source.Surface>,
        pcurve: borrowing OriginalFiniteBSplineCharts<Source.Pcurve>,maximumCharts: Int,
        limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalPeriodicNativeSurfaceLiftGraphs<Source>
}
