#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

/// Checked whole-law image evidence; this receipt does not select a contact domain.
public struct ExactPolynomialCurveMapEvidence<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    public let graph: ExactParametricGraph<Base>
    public let isConstant: Bool
    public let hasFiniteFibers: Bool
    public let derivativeMinors: [ExactPolynomial<ExactAlgebraicScalarDomain<Base>>]
    public let depth: ExactScalarDepth
    init(graph: ExactParametricGraph<Base>, isConstant: Bool, hasFiniteFibers: Bool,
        derivativeMinors: [ExactPolynomial<ExactAlgebraicScalarDomain<Base>>], depth: ExactScalarDepth) {
        self.graph = graph; self.isConstant = isConstant; self.hasFiniteFibers = hasFiniteFibers
        self.derivativeMinors = derivativeMinors; self.depth = depth
    }
}
