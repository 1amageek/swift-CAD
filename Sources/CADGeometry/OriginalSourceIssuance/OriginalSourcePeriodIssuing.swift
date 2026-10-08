#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public protocol OriginalSourcePeriodIssuing: Sendable {
    associatedtype Source: OriginalBSplineSourceReading
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering
    func issue<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        axis: Int, field: Field, limits: OriginalSourceIssuanceLimits, using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourcePeriodReceipt<Source,Field>
}
