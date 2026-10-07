#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

public struct ExactRealCellSample<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
 public let field: ExactAlgebraicScalarDomain<Base>
 public let coordinates: [ExactAlgebraicScalar<Base>]
 public let depth: ExactScalarDepth
 init(field: ExactAlgebraicScalarDomain<Base>, coordinates: [ExactAlgebraicScalar<Base>], depth: ExactScalarDepth) {
  self.field = field; self.coordinates = coordinates; self.depth = depth
 }
}
