#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

final class ExactRootSturm<F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    let polynomial: ExactPolynomial<F>
    let chain: [ExactPolynomial<F>]
    let depth: ExactScalarDepth
    init(polynomial: ExactPolynomial<F>, chain: [ExactPolynomial<F>], depth: ExactScalarDepth) {
        self.polynomial = polynomial; self.chain = chain; self.depth = depth
    }
}
