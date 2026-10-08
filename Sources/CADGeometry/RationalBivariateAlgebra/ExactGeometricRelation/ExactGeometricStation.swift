#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

public enum ExactGeometricStation<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    case xyz(ExactXYZ<Base>)
    case curveParameter(field: ExactAlgebraicScalarDomain<Base>, value: ExactAlgebraicScalar<Base>)
    case firstSurfaceUV(ExactUV<Base>)
    case secondSurfaceUV(ExactUV<Base>)
}
