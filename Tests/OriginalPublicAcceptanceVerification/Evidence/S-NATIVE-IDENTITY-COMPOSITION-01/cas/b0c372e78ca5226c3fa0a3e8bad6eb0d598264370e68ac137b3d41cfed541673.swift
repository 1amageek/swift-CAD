#if L1_ISOLATED_VERIFICATION
import L0
#endif

public struct ExactPolynomialSquareFreeFactor<F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    public let polynomial: ExactPolynomial<F>
    public let multiplicity: Int
    init(polynomial: ExactPolynomial<F>, multiplicity: Int) {
        self.polynomial = polynomial; self.multiplicity = multiplicity
    }
}
