#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

public struct ExactRealTopologySignInvariant<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
 public let polynomial: ExactPolynomial<ExactAlgebraicScalarDomain<Base>>
 public let incomingLaw: ExactPolynomial<ExactAlgebraicScalarDomain<Base>>?
 public let quotient: ExactPolynomial<ExactAlgebraicScalarDomain<Base>>?
 public let remainder: ExactPolynomial<ExactAlgebraicScalarDomain<Base>>?
 public let assumptions: [Int]
 public let reductions: [ExactPolynomialDivision<ExactAlgebraicScalarDomain<Base>>]
 public let axis: Int?
 public let constant: ExactSign?
}
