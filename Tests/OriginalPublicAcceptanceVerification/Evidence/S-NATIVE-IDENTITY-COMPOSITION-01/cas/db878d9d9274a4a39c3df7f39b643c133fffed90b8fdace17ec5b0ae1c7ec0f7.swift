#if L1_ISOLATED_VERIFICATION
import L0
#endif

public struct ExactPolynomialSquareFreeDecomposition<F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    let context: ExactPolynomialContext<F>
    public let unit: F.Value
    public let factors: [ExactPolynomialSquareFreeFactor<F>]
    public let depth: ExactScalarDepth
    init(context: ExactPolynomialContext<F>, unit: F.Value,
        factors: [ExactPolynomialSquareFreeFactor<F>], depth: ExactScalarDepth) {
        self.context = context; self.unit = unit; self.factors = factors; self.depth = depth
    }
}
