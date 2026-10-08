#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

public protocol ExactRealRootProducing: Sendable {
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering
    func count<A: ExactScalarAdmission & ~Copyable>(_ source: borrowing ExactRealRootSource<Field>,
        in domain: ExactRealRootInterval<Field.Value>, using admission: inout A
    ) throws(ExactRealRootFailure) -> ExactRealRootCount<Field>
    func count<A: ExactScalarAdmission & ~Copyable>(_ source: borrowing ExactRealRootSource<Field>,
        in domain: ExactRealRootInterval<Field.Value>, factoredBy factors: [ExactRealRootSource<Field>],
        using admission: inout A) throws(ExactRealRootFailure) -> ExactRealRootCount<Field>
    func isolate<A: ExactScalarAdmission & ~Copyable>(_ count: borrowing ExactRealRootCount<Field>,
        limits: ExactRealRootLimits, using admission: inout A
    ) throws(ExactRealRootFailure) -> ExactRealRootSet<Field>
    func isolate<A: ExactScalarAdmission & ~Copyable>(_ source: borrowing ExactRealRootSource<Field>,
        in domain: ExactRealRootInterval<Field.Value>, limits: ExactRealRootLimits, using admission: inout A
    ) throws(ExactRealRootFailure) -> ExactRealRootSet<Field>
    func isolate<A: ExactScalarAdmission & ~Copyable>(_ source: borrowing ExactRealRootSource<Field>,
        fromSortedExactCandidates candidates: [Field.Value], limits: ExactRealRootLimits, using admission: inout A
    ) throws(ExactRealRootFailure) -> ExactRealRootSet<Field>
}
