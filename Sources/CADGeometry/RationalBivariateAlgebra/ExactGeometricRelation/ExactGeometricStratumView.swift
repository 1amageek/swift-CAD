#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

/// Owner-backed collection; subscripting never materializes another array.
public struct ExactGeometricStratumView<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: RandomAccessCollection, Sendable where Base.Source == Base.Value {
    public typealias Index = Int
    public typealias Element = ExactGeometricStratumRecord
    let owner: ExactGeometricRelationStorage<Base>
    public var startIndex: Int { 0 }
    public var endIndex: Int { owner.payload.records.count }
    public subscript(position: Int) -> Element { owner.payload.records[position] }
}
