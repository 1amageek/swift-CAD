#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

final class ExactRealCellPartitionStorage<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
 let source: ExactRealCellSource<Base>
 let levels: [ExactRealCellProjectionLevel<Base>]
 let records: [ExactRealCellRecord<Base>]
 let stacks: [ExactRealCellStack<Base>]
 let leaves: [Int]
 let depth: ExactScalarDepth
 init(source: ExactRealCellSource<Base>, levels: [ExactRealCellProjectionLevel<Base>], records: [ExactRealCellRecord<Base>],
  stacks: [ExactRealCellStack<Base>], leaves: [Int], depth: ExactScalarDepth) {
  self.source=source; self.levels=levels; self.records=records; self.stacks=stacks; self.leaves=leaves; self.depth=depth
 }
}
