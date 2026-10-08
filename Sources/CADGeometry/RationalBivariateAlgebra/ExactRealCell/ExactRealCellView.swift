#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

public struct ExactRealCellView<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: RandomAccessCollection, Sendable where Base.Source == Base.Value {
 public typealias Index = Int
 public typealias Element = ExactRealCellID<Base>
 let owner: ExactRealCellPartitionStorage<Base>
 private let cellOrdinals: [Int]
 init(owner: ExactRealCellPartitionStorage<Base>, indices: [Int]) {
  self.owner = owner; cellOrdinals = indices
 }
 public var startIndex: Int { 0 }
 public var endIndex: Int { cellOrdinals.count }
 public subscript(position: Int) -> Element { .init(owner:owner,index:cellOrdinals[position]) }
}
