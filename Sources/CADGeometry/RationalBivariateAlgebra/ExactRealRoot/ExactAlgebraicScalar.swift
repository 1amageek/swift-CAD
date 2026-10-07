#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

public struct ExactAlgebraicScalar<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    let context: ExactAlgebraicContext<Base>
    let storage: ExactAlgebraicStorage<Base>
    public let depth: ExactScalarDepth
    init(context: ExactAlgebraicContext<Base>, storage: ExactAlgebraicStorage<Base>, depth: ExactScalarDepth) {
        self.context = context; self.storage = storage; self.depth = depth
    }
}
