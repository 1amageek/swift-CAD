#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Immutable correspondence retaining both the original and transferred root owners.
public struct ExactRealRootTransport<F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    public let original: ExactRealRoot<F>
    public let transferred: ExactRealRoot<F>
    public let depth: ExactScalarDepth
    init(original: ExactRealRoot<F>, transferred: ExactRealRoot<F>, depth: ExactScalarDepth) {
        self.original = original; self.transferred = transferred; self.depth = depth
    }
}
