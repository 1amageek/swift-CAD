#if L5_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
#endif

/// Complete parameter topology, without an assertion about XYZ image dimensions.
public struct ExactParametricRelation<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    public let original: ExactParametricRelationSource<Base>
    public let components: ExactRealComponents<Base>
    public var selection: ExactRealCellSelection<Base> { components.incidence.selection }
    init(original: ExactParametricRelationSource<Base>, components: ExactRealComponents<Base>) {
        self.original = original; self.components = components
    }
}
