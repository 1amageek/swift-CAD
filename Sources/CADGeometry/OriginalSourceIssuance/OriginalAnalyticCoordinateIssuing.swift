#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public protocol OriginalAnalyticCoordinateIssuing: Sendable {
    associatedtype Source: OriginalAnalyticCoordinateReading
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting
    func issue<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,field: borrowing Field,
        limits: OriginalSourceIssuanceLimits,using admission: inout A) throws(OriginalSourceIssuanceFailure) -> OriginalAnalyticCoordinateLawReceipt<Source,Field>
}
