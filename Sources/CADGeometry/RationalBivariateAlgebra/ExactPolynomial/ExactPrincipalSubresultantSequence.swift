#if L1_ISOLATED_VERIFICATION
import L0
#endif

/// Complete index-preserving principal coefficients in the original variable basis.
public struct ExactPrincipalSubresultantSequence<F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    public let first: ExactPolynomial<F>
    public let second: ExactPolynomial<F>
    public let variable: Int
    public let values: [ExactPolynomial<F>]
    public let depth: ExactScalarDepth
}
