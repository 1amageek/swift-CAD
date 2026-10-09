#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Prepares every nonperiodic finite native span without deriving support from a union.
public protocol OriginalFiniteBSplineChartPreparing: Sendable {
    associatedtype Source: OriginalBSplineSourceReading
    func prepare<A: ExactScalarAdmission & ~Copyable>(
        source: borrowing OriginalSourceBinding<Source>, field: borrowing OriginalExactScalarDomain,
        maximumCharts: Int, limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalFiniteBSplineCharts<Source>
}
