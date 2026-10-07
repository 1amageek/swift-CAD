#if L5_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
#endif

/// Exact E = W*Q proof, valid for zero testing only under the retained W != 0.
public struct ExactParametricGuardDivision<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    public let equationIndex: Int
    public let guardIndex: Int
    public let dividend: ExactPolynomial<ExactAlgebraicScalarDomain<Base>>
    public let division: ExactPolynomialDivision<ExactAlgebraicScalarDomain<Base>>
    init(equationIndex: Int, guardIndex: Int, dividend: ExactPolynomial<ExactAlgebraicScalarDomain<Base>>,
         division: ExactPolynomialDivision<ExactAlgebraicScalarDomain<Base>>) {
        self.equationIndex = equationIndex; self.guardIndex = guardIndex
        self.dividend = dividend; self.division = division
    }
}
