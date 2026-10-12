#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

public struct ExactRealTopologyFactor<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
 public let boundary: ExactRealCellBoundaryRoot<Base>
 public let factor: ExactPolynomial<ExactAlgebraicScalarDomain<Base>>
 public let quotient: ExactPolynomial<ExactAlgebraicScalarDomain<Base>>
 public let leading: ExactSign
}
