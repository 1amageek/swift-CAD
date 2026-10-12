#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Complete exact signs at one retained original root, in the original query order.
public struct ExactRealRootSigns<F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    public let root: ExactRealRoot<F>
    public let queries: [ExactRealRootSource<F>]
    public let values: [ExactSign]
    public let depth: ExactScalarDepth
    init(root: ExactRealRoot<F>, queries: [ExactRealRootSource<F>], values: [ExactSign], depth: ExactScalarDepth) {
        self.root = root; self.queries = queries; self.values = values; self.depth = depth
    }
}
