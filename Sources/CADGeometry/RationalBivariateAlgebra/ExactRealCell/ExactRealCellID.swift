#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

public struct ExactRealCellID<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable, Equatable where Base.Source == Base.Value {
 let owner: ExactRealCellPartitionStorage<Base>
 let index: Int
 public var dimension: Int { owner.records[index].dimension }
 public var signs: [ExactSign] { owner.records[index].signs }
 public static func == (lhs: Self, rhs: Self) -> Bool { lhs.owner === rhs.owner && lhs.index == rhs.index }
}
