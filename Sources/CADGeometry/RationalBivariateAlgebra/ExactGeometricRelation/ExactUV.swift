#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

public struct ExactUV<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    public let field: ExactAlgebraicScalarDomain<Base>
    public let u: ExactAlgebraicScalar<Base>
    public let v: ExactAlgebraicScalar<Base>
    public init(field: ExactAlgebraicScalarDomain<Base>, u: ExactAlgebraicScalar<Base>, v: ExactAlgebraicScalar<Base>) {
        self.field = field; self.u = u; self.v = v
    }
}
