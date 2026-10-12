#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

/// A whole-cell sign identity issued from an original partition's projection cut law.
public struct ExactRealCellSignInvariant<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
 public let partition: ExactRealCellPartition<Base>
 public let polynomial: ExactPolynomial<ExactAlgebraicScalarDomain<Base>>
 public let projectionLaw: ExactPolynomial<ExactAlgebraicScalarDomain<Base>>
 /// The exact identity is polynomial = quotient * projectionLaw, with zero remainder.
 public let quotient: ExactPolynomial<ExactAlgebraicScalarDomain<Base>>
 public let remainder: ExactPolynomial<ExactAlgebraicScalarDomain<Base>>
 public let axis: Int
 public let lawIndex: Int
 public let orientation: ExactSign
 public let depth: ExactScalarDepth

 init(partition: ExactRealCellPartition<Base>, polynomial: ExactPolynomial<ExactAlgebraicScalarDomain<Base>>,
  projectionLaw: ExactPolynomial<ExactAlgebraicScalarDomain<Base>>,
  quotient: ExactPolynomial<ExactAlgebraicScalarDomain<Base>>, remainder: ExactPolynomial<ExactAlgebraicScalarDomain<Base>>,
  axis: Int, lawIndex: Int, orientation: ExactSign, depth: ExactScalarDepth) {
  self.partition = partition; self.polynomial = polynomial; self.projectionLaw = projectionLaw
  self.quotient = quotient; self.remainder = remainder; self.axis = axis; self.lawIndex = lawIndex
  self.orientation = orientation; self.depth = depth
 }
}
