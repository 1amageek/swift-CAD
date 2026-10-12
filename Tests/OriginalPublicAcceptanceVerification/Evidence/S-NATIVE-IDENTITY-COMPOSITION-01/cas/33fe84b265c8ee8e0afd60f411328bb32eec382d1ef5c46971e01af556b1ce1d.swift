#if L1_ISOLATED_VERIFICATION
import L0
#endif

public struct ExactPolynomialDivision<F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    public let quotient: ExactPolynomial<F>
    public let remainder: ExactPolynomial<F>
    init(quotient: ExactPolynomial<F>, remainder: ExactPolynomial<F>) {
        self.quotient = quotient; self.remainder = remainder
    }
}
