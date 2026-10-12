#if L1_ISOLATED_VERIFICATION
import L0
#endif

/// Continuations replace native recursion across coefficient rings of arbitrary finite arity.
enum ExactPolynomialGCDTask<F: ExactScalarArithmetic & ExactScalarOrdering> {
    typealias P = ExactPolynomial<F>
    case gcd(P, P)
    case content(P, Int)
    case contentStep([ExactPolynomialDegreeCoefficient<F>], Int, P)
    case afterContentStep([ExactPolynomialDegreeCoefficient<F>], Int)
    case afterFirstContent(P, P, Int)
    case afterSecondContent(P, P, Int, P)
    case afterSharedContent(P, P, Int)
    case prs(P, P, P, Int)
    case afterRemainderContent(P, P, P, Int)
}
