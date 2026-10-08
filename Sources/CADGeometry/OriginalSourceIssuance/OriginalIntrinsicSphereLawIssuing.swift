#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public protocol OriginalIntrinsicSphereLawIssuing: Sendable {
    associatedtype Source: OriginalIntrinsicSphereSourceReading
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering
    func period<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,field: Field,
        limits: OriginalSourceIssuanceLimits,using admission: inout A) throws(OriginalSourceIssuanceFailure) -> OriginalSourcePeriodReceipt<Source,Field>
    func pole<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,latitude: Field.Value,field: Field,
        limits: OriginalSourceIssuanceLimits,using admission: inout A) throws(OriginalSourceIssuanceFailure) -> OriginalSourcePoleReceipt<Source,Field>
}
