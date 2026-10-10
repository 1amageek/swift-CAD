#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public protocol OriginalSourceAffineActionIssuing: Sendable {
    associatedtype Source: Sendable
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering
    func issue<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,field: borrowing Field,
        limits: OriginalSourceIssuanceLimits,using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceAffineActionReceipt<Source,Field>
}
