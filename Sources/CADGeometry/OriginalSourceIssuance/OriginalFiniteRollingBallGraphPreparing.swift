#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public protocol OriginalFiniteRollingBallGraphPreparing: Sendable {
    associatedtype Source: OriginalRollingBallChildSourceReading
    associatedtype ChildEvidence: Sendable
    associatedtype ChildCoverage: Sendable
    func prepare<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        center: borrowing OriginalCompleteCurveGraphs<Source.Child,ChildEvidence,ChildCoverage>,
        first: borrowing OriginalCompleteCurveGraphs<Source.Child,ChildEvidence,ChildCoverage>,
        second: borrowing OriginalCompleteCurveGraphs<Source.Child,ChildEvidence,ChildCoverage>,
        maximumCharts: Int,limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalFiniteRollingBallGraphs<Source,ChildEvidence,ChildCoverage>
}
