#if L5_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
#endif

/// W*E = G*Q+R proves E=0 iff R=0 under the retained W!=0 and G=0.
public struct ExactParametricGuardRemainder<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    public let equationIndex: Int
    public let nonzeroGuardIndex: Int
    public let equalityGuardIndex: Int
    public let equation: ExactPolynomial<ExactAlgebraicScalarDomain<Base>>
    public let dividend: ExactPolynomial<ExactAlgebraicScalarDomain<Base>>
    public let division: ExactPolynomialDivision<ExactAlgebraicScalarDomain<Base>>
    init(equationIndex: Int, nonzeroGuardIndex: Int, equalityGuardIndex: Int,
        equation: ExactPolynomial<ExactAlgebraicScalarDomain<Base>>, dividend: ExactPolynomial<ExactAlgebraicScalarDomain<Base>>,
        division: ExactPolynomialDivision<ExactAlgebraicScalarDomain<Base>>) {
        self.equationIndex=equationIndex; self.nonzeroGuardIndex=nonzeroGuardIndex; self.equalityGuardIndex=equalityGuardIndex
        self.equation=equation; self.dividend=dividend; self.division=division
    }
}
