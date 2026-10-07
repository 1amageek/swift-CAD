#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

public struct ExactRealRootCount<F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    public let source: ExactRealRootSource<F>
    public let domain: ExactRealRootInterval<F.Value>
    public let classification: ExactRealRootClassification
    public let depth: ExactScalarDepth
    let factors: [(proof: ExactRootSturm<F>, multiplicity: Int)]
    init(source: ExactRealRootSource<F>, domain: ExactRealRootInterval<F.Value>,
        classification: ExactRealRootClassification, factors: [(proof: ExactRootSturm<F>, multiplicity: Int)], depth: ExactScalarDepth) {
        self.source = source; self.domain = domain; self.classification = classification
        self.factors = factors; self.depth = depth
    }
}
