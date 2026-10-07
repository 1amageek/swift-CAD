#if L1_ISOLATED_VERIFICATION
import L0
#endif

struct ExactPolynomialDegreeCoefficient<F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    let degree: Int
    let polynomial: ExactPolynomial<F>
}
