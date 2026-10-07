#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

public struct ExactRealCellView<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: RandomAccessCollection, Sendable where Base.Source == Base.Value {
 public typealias Index = Int
 public typealias Element = ExactRealCellID<Base>
 let owner: ExactRealCellPartitionStorage<Base>
 let indices: [Int]
 public var startIndex: Int { 0 }
 public var endIndex: Int { indices.count }
 public subscript(position: Int) -> Element { .init(owner:owner,index:indices[position]) }
}
