#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public protocol OriginalPlaneBasisIssuing: Sendable {
    associatedtype Source: OriginalPlaneSourceReading
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering
    /// Candidate square roots belong to the caller's coefficient field. They are
    /// proved here; supplying an approximate or wrong root cannot mint a receipt.
    func issue<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,field: Field,
        firstLength: Field.Value,normalLength: Field.Value,limits: OriginalSourceIssuanceLimits,
        using admission: inout A) throws(OriginalSourceIssuanceFailure) -> OriginalPlaneBasisReceipt<Source,Field>
}
