#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

enum ExactAlgebraicStorage<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    case base(Base.Value)
    case fraction(ExactPolynomial<ExactAlgebraicScalarDomain<Base>>, ExactPolynomial<ExactAlgebraicScalarDomain<Base>>)
}
