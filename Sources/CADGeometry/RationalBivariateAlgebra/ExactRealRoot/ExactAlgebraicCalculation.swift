#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Immutable correspondence between the authored root and a local calculation law.
public final class ExactAlgebraicCalculation<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    public typealias Field = ExactAlgebraicScalarDomain<Base>
    public let originalRoot: ExactRealRoot<Field>
    public let selectedRoot: ExactRealRoot<Field>
    public let definingSource: ExactRealRootSource<Field>
    public let depth: ExactScalarDepth
    init(originalRoot: ExactRealRoot<Field>, selectedRoot: ExactRealRoot<Field>,
        definingSource: ExactRealRootSource<Field>, depth: ExactScalarDepth) {
        self.originalRoot = originalRoot; self.selectedRoot = selectedRoot
        self.definingSource = definingSource; self.depth = depth
    }
}
