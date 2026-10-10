#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// The retained source's position action on its original descendant.
public struct OriginalSourceAffineActionReceipt<S: Sendable,F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    public let source: OriginalSourceBinding<S>
    public let action: OriginalSourceAffineAction<F>
    init(source: OriginalSourceBinding<S>,action: OriginalSourceAffineAction<F>) {
        self.source = source;self.action = action
    }
    public func admitProof<A: ExactScalarAdmission & ~Copyable>(limits: OriginalSourceIssuanceLimits,using a: inout A) throws(OriginalSourceIssuanceFailure) {
        do {
            try a.checkpoint();try a.consumeWork(1);try source.require(limits)
            try action.admitted(using:&a);try a.checkpoint()
        } catch { throw .init(preserving:error) }
    }
}
