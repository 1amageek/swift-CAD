#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

public struct ExactXYZ<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    public let field: ExactAlgebraicScalarDomain<Base>
    public let x: ExactAlgebraicScalar<Base>
    public let y: ExactAlgebraicScalar<Base>
    public let z: ExactAlgebraicScalar<Base>
    public init(field: ExactAlgebraicScalarDomain<Base>, x: ExactAlgebraicScalar<Base>, y: ExactAlgebraicScalar<Base>, z: ExactAlgebraicScalar<Base>) {
        self.field = field; self.x = x; self.y = y; self.z = z
    }
}
