#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

public struct ExactRealRoot<F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    public let source: ExactRealRootSource<F>
    public let multiplicity: Int
    public let ordinal: Int
    public let isolation: ExactRealRootInterval<F.Value>
    public let depth: ExactScalarDepth
    let proof: ExactRootSturm<F>
    init(source: ExactRealRootSource<F>, multiplicity: Int, ordinal: Int,
        isolation: ExactRealRootInterval<F.Value>, proof: ExactRootSturm<F>, depth: ExactScalarDepth) {
        self.source = source; self.multiplicity = multiplicity; self.ordinal = ordinal
        self.isolation = isolation; self.proof = proof; self.depth = depth
    }
}
