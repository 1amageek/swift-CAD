#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

/// Owner-backed read-only view of one complete projection level.
public struct ExactRealCellProjectionEvidence<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: RandomAccessCollection, Sendable where Base.Source == Base.Value {
    public typealias Index = Int
    public typealias Element = ExactRealCellProjectionWitness<Base>
    let owner: ExactRealCellPartitionStorage<Base>
    public let axis: Int
    public var startIndex: Int { 0 }
    public var endIndex: Int { owner.levels[axis].witnesses.count }
    public subscript(position: Int) -> Element { owner.levels[axis].witnesses[position] }
    public var parentConditions: [ExactRealCellProjectionBinding<Base>] { owner.levels[axis].bindings }
    public var cutLawCount: Int { owner.levels[axis].cutLawCount }
}
