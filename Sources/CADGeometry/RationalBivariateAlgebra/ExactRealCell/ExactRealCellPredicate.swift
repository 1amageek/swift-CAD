#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

public struct ExactRealCellPredicate<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    public let source: ExactRealCellSource<Base>
    public let instructions: [ExactRealCellInstruction]
    public let depth: ExactScalarDepth
    init(source: ExactRealCellSource<Base>, instructions: [ExactRealCellInstruction], depth: ExactScalarDepth) {
        self.source = source; self.instructions = instructions; self.depth = depth
    }
}
