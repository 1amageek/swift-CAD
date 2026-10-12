#if L5_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
#endif

/// Mathematical position graph: XYZ/W occupy laws 0...3; the predicate guards all variables.
/// Original local parameters are the canonical prefix; remaining variables are auxiliary.
public struct ExactParametricGraph<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    public let predicate: ExactRealCellPredicate<Base>
    public let parameterCount: Int
    public var variableCount: Int { predicate.source.variableCount }
    init(predicate: ExactRealCellPredicate<Base>, parameterCount: Int) {
        self.predicate = predicate; self.parameterCount = parameterCount
    }
}
