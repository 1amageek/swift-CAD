#if L5_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
#endif

/// Retains each law's exact division identity under an issued zero factor.
public struct ExactParametricConstraintDivision<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    public let lawIndex: Int
    public let factorIndex: Int
    public let dividend: ExactPolynomial<ExactAlgebraicScalarDomain<Base>>
    public let division: ExactPolynomialDivision<ExactAlgebraicScalarDomain<Base>>
}
