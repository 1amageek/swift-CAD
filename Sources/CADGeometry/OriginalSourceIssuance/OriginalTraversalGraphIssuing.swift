#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Issues original curve correspondence with every child preimage and guard.
public protocol OriginalTraversalGraphIssuing: Sendable {
    associatedtype Source: OriginalTraversalSourceReading
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting
    associatedtype ChildEvidence: Sendable
    func issue<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        child: borrowing OriginalParametricGraphReceipt<Source.Child,Field,ChildEvidence>,
        limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalParametricGraphReceipt<Source,Field,OriginalCurveParameterGraphEvidence<Source.Child,Field,ChildEvidence>>
}
