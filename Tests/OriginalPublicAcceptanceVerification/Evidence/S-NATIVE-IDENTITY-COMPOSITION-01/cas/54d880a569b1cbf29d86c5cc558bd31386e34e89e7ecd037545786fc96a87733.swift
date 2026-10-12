#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public protocol OriginalSourceBindingIssuing: Sendable {
    associatedtype Input: Sendable
    associatedtype Source: Sendable
    func bind<A: ExactScalarAdmission & ~Copyable>(
        _ input: borrowing Input, limits: OriginalSourceIssuanceLimits,
        using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceBinding<Source>
}
