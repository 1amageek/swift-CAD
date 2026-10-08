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
 /// Non-nil only when an exact nonzero constant multiple of an original source law is proved.
 public let sourceLawIndex: Int?
 public let sourceLawOrientation: ExactSign?
 /// Issued whole-cell proof for a retained L3 projected cut law.
 public let projectionInvariant: ExactRealCellSignInvariant<Base>?
 /// True only for an affine atom whose exact square is the retained projection polynomial.
 public let projectionProvesSquare: Bool
 init(polynomial: ExactPolynomial<ExactAlgebraicScalarDomain<Base>>,
  incomingLaw: ExactPolynomial<ExactAlgebraicScalarDomain<Base>>?,
  quotient: ExactPolynomial<ExactAlgebraicScalarDomain<Base>>?,
  remainder: ExactPolynomial<ExactAlgebraicScalarDomain<Base>>?, assumptions: [Int],
  reductions: [ExactPolynomialDivision<ExactAlgebraicScalarDomain<Base>>], axis: Int?,
  constant: ExactSign?, sourceLawIndex: Int? = nil, sourceLawOrientation: ExactSign? = nil, projectionInvariant: ExactRealCellSignInvariant<Base>? = nil, projectionProvesSquare: Bool = false) {
  self.polynomial = polynomial; self.incomingLaw = incomingLaw; self.quotient = quotient
  self.remainder = remainder; self.assumptions = assumptions; self.reductions = reductions
  self.axis = axis; self.constant = constant; self.sourceLawIndex = sourceLawIndex
  self.sourceLawOrientation = sourceLawOrientation; self.projectionInvariant = projectionInvariant; self.projectionProvesSquare = projectionProvesSquare
 }
}
