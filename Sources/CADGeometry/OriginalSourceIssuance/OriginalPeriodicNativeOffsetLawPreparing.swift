#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public protocol OriginalPeriodicNativeOffsetLawPreparing: Sendable {
    associatedtype Source: OriginalOffsetSourceReading where Source.Child: OriginalBSplineSourceReading
    func prepare<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        child: borrowing OriginalBSplineFundamentalCharts<Source.Child>,maximumCharts: Int,
        limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalPeriodicNativeOffsetLawFamily<Source>
}
