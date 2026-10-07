#if L5_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
#endif

/// A source-issued rational map; homogeneous law order is X, Y, Z, W.
public struct ExactParametricMap<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    public let original: ExactRealCellSource<Base>
    public var parameterCount: Int { original.variableCount }
    init(original: ExactRealCellSource<Base>) { self.original = original }
}
