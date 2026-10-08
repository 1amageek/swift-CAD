#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Retained original roots and an exactly certified value strictly between them.
public struct ExactRealRootSeparation<F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    public let left: ExactRealRoot<F>
    public let right: ExactRealRoot<F>
    public let value: F.Value
    public let depth: ExactScalarDepth
    init(left: ExactRealRoot<F>, right: ExactRealRoot<F>, value: F.Value, depth: ExactScalarDepth) {
        self.left = left; self.right = right; self.value = value; self.depth = depth
    }
}
