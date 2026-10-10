#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Complete retained normalized pcurve laws over a certified periodic Native host.
public protocol OriginalPeriodicRetainedSurfaceLiftGraphPreparing: Sendable {
    associatedtype Source: OriginalRetainedSurfaceLiftSourceReading
    func prepare<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        surface: borrowing OriginalBSplineFundamentalCharts<Source.Surface>,
        pcurve: borrowing OriginalFiniteRetainedCurveCharts<Source.Pcurve>,maximumCharts: Int,
        limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalPeriodicNativeSurfaceLiftGraphs<Source>
}
