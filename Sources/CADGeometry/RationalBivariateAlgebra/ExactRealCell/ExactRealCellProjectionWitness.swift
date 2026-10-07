#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

enum ExactRealCellProjectionWitness<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    typealias Polynomial = ExactPolynomial<ExactAlgebraicScalarDomain<Base>>
    case normalization(original: Polynomial, result: Polynomial)
    case derivative(original: Polynomial, result: Polynomial, axis: Int)
    case coefficient(original: Polynomial, result: Polynomial, axis: Int, degree: Int)
    case principal(first: Polynomial, second: Polynomial, result: Polynomial, axis: Int, index: Int)
}
