#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public protocol OriginalFiniteRetainedSurfaceLiftGraphPreparing: Sendable {
    associatedtype Source: OriginalRetainedSurfaceLiftSourceReading
    func prepare<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        surface: borrowing OriginalFiniteBSplineCharts<Source.Surface>,
        pcurve: borrowing OriginalFiniteRetainedCurveCharts<Source.Pcurve>, maximumCharts: Int,
        limits: OriginalSourceIssuanceLimits, using a: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalFiniteRetainedSurfaceLiftGraphs<Source>
}
