#if L1_ISOLATED_VERIFICATION
import L0
#endif

/// Immutable identity, variable basis and retained coefficient operation owner.
final class ExactPolynomialContext<F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    let field: F
    let variableCount: Int
    let zero: F.Value
    let one: F.Value
    let depth: ExactScalarDepth
    init(field: F, variableCount: Int, zero: F.Value, one: F.Value, depth: ExactScalarDepth) {
        self.field = field; self.variableCount = variableCount
        self.zero = zero; self.one = one; self.depth = depth
    }
}
