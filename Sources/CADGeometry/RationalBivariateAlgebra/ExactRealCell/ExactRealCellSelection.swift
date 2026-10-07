#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

public struct ExactRealCellSelection<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
 public let partition: ExactRealCellPartition<Base>
 public let predicate: ExactRealCellPredicate<Base>
 let selected: [Int]
 public var cells: ExactRealCellView<Base> { .init(owner:partition.owner,indices:selected) }
 public let depth: ExactScalarDepth
}
