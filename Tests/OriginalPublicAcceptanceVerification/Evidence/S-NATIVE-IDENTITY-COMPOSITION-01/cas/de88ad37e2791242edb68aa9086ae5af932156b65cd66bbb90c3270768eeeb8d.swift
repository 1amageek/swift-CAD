#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

public struct ExactRealCellCondition<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
 public let cell: ExactRealCellID<Base>
 /// Retained root ordinals/sector slots, one per source axis; these identify a branch, not a sample.
 public let branches: [Int]
 public let depth: ExactScalarDepth
}
