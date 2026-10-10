#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Transports position while retaining every original child parameter and guard.
public protocol OriginalSpatialGraphIssuing: Sendable {
    associatedtype Source: OriginalSpatialSourceReading
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting
    associatedtype ChildEvidence: Sendable
    func issue<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        child: borrowing OriginalParametricGraphReceipt<Source.Child,Field,ChildEvidence>,
        limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalParametricGraphReceipt<Source,Field,OriginalSpatialGraphEvidence<Source.Child,Field,ChildEvidence>>
}
