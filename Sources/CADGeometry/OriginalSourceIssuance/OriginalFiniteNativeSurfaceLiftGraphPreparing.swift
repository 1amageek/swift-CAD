#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public protocol OriginalFiniteNativeSurfaceLiftGraphPreparing: Sendable {
    associatedtype Source: OriginalSurfaceLiftSourceReading
    func prepare<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        surface: borrowing OriginalFiniteBSplineCharts<Source.Surface>,
        pcurve: borrowing OriginalFiniteBSplineCharts<Source.Pcurve>, maximumCharts: Int,
        limits: OriginalSourceIssuanceLimits, using a: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalFiniteNativeSurfaceLiftGraphs<Source>
}
