#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Issues the complete cosine zero set of a bounded original physical circle law.
public protocol OriginalAnalyticCosineZeroIssuing {
    associatedtype Source: OriginalAnalyticCoordinateReading
    associatedtype Field: OriginalPiGenerating
    func issue<A: ExactScalarAdmission & ~Copyable>(
        law: borrowing OriginalAnalyticCoordinateLawReceipt<Source,Field>,
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalAnalyticCosineZeroReceipt<Source,Field>
}
