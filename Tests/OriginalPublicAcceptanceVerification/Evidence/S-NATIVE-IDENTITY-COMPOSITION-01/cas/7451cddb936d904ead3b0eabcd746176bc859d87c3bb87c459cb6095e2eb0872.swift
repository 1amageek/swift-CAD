#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

final class ExactRealRootContext<F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    let field: F
    let input: ExactPolynomialDomain<F>
    let univariate: ExactPolynomialDomain<F>
    let depth: ExactScalarDepth
    init(field: F, input: ExactPolynomialDomain<F>, univariate: ExactPolynomialDomain<F>, depth: ExactScalarDepth) {
        self.field = field; self.input = input; self.univariate = univariate; self.depth = depth
    }
}
