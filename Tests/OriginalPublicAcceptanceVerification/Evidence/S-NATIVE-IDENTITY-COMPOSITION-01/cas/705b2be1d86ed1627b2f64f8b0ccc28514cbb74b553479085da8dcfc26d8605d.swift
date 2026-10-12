#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public protocol OriginalFiniteNativeOffsetLawPreparing {
    associatedtype Source:OriginalOffsetSourceReading where Source.Child:OriginalBSplineSourceReading
    func prepare<A:ExactScalarAdmission & ~Copyable>(source:borrowing OriginalSourceBinding<Source>,
        child:borrowing OriginalFiniteBSplineCharts<Source.Child>,maximumCharts:Int,
        limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure)
        -> OriginalFiniteNativeOffsetLawFamily<Source>
}
