#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public protocol OriginalParametricGraphIssuing:Sendable {
    associatedtype Source:Sendable
    associatedtype Field:ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting
    associatedtype Evidence:Sendable
    func issue<A: ExactScalarAdmission & ~Copyable>(_ evidence:borrowing Evidence,limits:OriginalSourceIssuanceLimits,
        using admission:inout A)
        throws(OriginalSourceIssuanceFailure)->OriginalParametricGraphReceipt<Source,Field,Evidence>
}
