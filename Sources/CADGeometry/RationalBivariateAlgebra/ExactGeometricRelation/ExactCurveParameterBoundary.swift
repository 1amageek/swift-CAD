#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

/// An exact source root or an original parameter-domain endpoint.
public enum ExactCurveParameterBoundary<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    case root(ExactRealCellBoundaryRoot<Base>)
    case domain(ExactRealRootBound<ExactAlgebraicScalar<Base>>)
}
