#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

final class ExactAlgebraicContext<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    let base: Base
    let parent: ExactAlgebraicContext<Base>?
    let root: ExactRealRoot<ExactAlgebraicScalarDomain<Base>>?
    let level: Int
    let maximumExtensionLevel: Int
    let depth: ExactScalarDepth
    init(base: Base, parent: ExactAlgebraicContext<Base>?, root: ExactRealRoot<ExactAlgebraicScalarDomain<Base>>?,
        level: Int, maximumExtensionLevel: Int, depth: ExactScalarDepth) {
        self.base = base; self.parent = parent; self.root = root; self.level = level
        self.maximumExtensionLevel = maximumExtensionLevel; self.depth = depth
    }
}
