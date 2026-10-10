#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public protocol OriginalFiniteRetainedAtlasLiftGraphPreparing: Sendable {
    associatedtype Source: OriginalRetainedAtlasLiftSourceReading
    func prepare<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        surface: borrowing OriginalFiniteRetainedSurfaceCharts<Source.Surface>,
        pcurve: borrowing OriginalFiniteRetainedCurveCharts<Source.Pcurve>,maximumCharts: Int,
        limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalFiniteRetainedSurfaceLiftGraphs<Source>
}
