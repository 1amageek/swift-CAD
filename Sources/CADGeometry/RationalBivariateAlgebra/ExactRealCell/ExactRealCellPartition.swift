#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

public struct ExactRealCellPartition<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
 let owner: ExactRealCellPartitionStorage<Base>
 public var source: ExactRealCellSource<Base> { owner.source }
 public var cells: ExactRealCellView<Base> { .init(owner:owner,indices:owner.leaves) }
 public var storedCellCount: Int { owner.records.count }
 public var depth: ExactScalarDepth { owner.depth }
}
