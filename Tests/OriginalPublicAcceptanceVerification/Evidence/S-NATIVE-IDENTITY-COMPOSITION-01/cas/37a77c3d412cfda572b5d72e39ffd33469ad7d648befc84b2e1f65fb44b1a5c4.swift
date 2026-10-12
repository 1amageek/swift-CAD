#if L1_ISOLATED_VERIFICATION
import L0
#endif

/// Reuse must admit the receipt's depth, including proofs lost from a bare scalar value.
public struct ExactPolynomialEvaluation<F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    let context: ExactPolynomialContext<F>
    public let value: F.Value
    public let depth: ExactScalarDepth
    init(context: ExactPolynomialContext<F>, value: F.Value, depth: ExactScalarDepth) {
        self.context = context; self.value = value; self.depth = depth
    }
}
