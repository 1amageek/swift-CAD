#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

public struct ExactRealRootSet<F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    public let count: ExactRealRootCount<F>
    public var source: ExactRealRootSource<F> { count.source }
    public var domain: ExactRealRootInterval<F.Value> { count.domain }
    public var classification: ExactRealRootClassification { count.classification }
    public let roots: [ExactRealRoot<F>]
    public let depth: ExactScalarDepth
    init(count: ExactRealRootCount<F>, roots: [ExactRealRoot<F>], depth: ExactScalarDepth) {
        self.count = count; self.roots = roots; self.depth = depth
    }
}
