#if L1_ISOLATED_VERIFICATION
import L0
#endif

public struct ExactPolynomial<F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    let context: ExactPolynomialContext<F>
    public let terms: [ExactPolynomialTerm<F.Value>]
    public let depth: ExactScalarDepth
    public var variableCount: Int { context.variableCount }
    public var termCount: Int { terms.count }
    init(context: ExactPolynomialContext<F>, terms: [ExactPolynomialTerm<F.Value>], depth: ExactScalarDepth) {
        self.context = context; self.terms = terms; self.depth = depth
    }
}
