#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public protocol OriginalPlaneBasisIssuing: Sendable {
    associatedtype Source: OriginalPlaneSourceReading
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering
    /// Returns 0 (X) or 1 (Y), choosing the smaller absolute source normal
    /// component; ties choose X. Candidate firstLength uses N cross this axis.
    func referenceAxis<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        limits: OriginalSourceIssuanceLimits,using admission: inout A) throws(OriginalSourceIssuanceFailure) -> Int
    /// Candidate square roots belong to the caller's coefficient field. They are
    /// proved here; supplying an approximate or wrong root cannot mint a receipt.
    func issue<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,field: Field,
        firstLength: Field.Value,normalLength: Field.Value,limits: OriginalSourceIssuanceLimits,
        using admission: inout A) throws(OriginalSourceIssuanceFailure) -> OriginalPlaneBasisReceipt<Source,Field>
}
