#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

public struct ExactRealRootSource<F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    let context: ExactRealRootContext<F>
    public let original: ExactPolynomial<F>
    public let variable: Int
    public let refinementAxis: ExactScalarRootAxis
    public let depth: ExactScalarDepth
    let law: ExactPolynomial<F>
    init(context: ExactRealRootContext<F>, original: ExactPolynomial<F>, variable: Int,
        refinementAxis: ExactScalarRootAxis, law: ExactPolynomial<F>, depth: ExactScalarDepth) {
        self.context = context; self.original = original; self.variable = variable
        self.refinementAxis = refinementAxis; self.law = law; self.depth = depth
    }
}
