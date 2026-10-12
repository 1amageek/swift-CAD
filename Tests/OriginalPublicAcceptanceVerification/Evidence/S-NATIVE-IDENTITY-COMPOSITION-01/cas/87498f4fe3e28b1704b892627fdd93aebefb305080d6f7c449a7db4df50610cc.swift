#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

/// Owner-backed view of all compatible lifted cells, including nonunique witnesses.
public struct ExactRealProjectionLifts<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: RandomAccessCollection, Sendable where Base.Source == Base.Value {
    public typealias Index = Int
    public typealias Element = ExactRealCellID<Base>
    public let original: ExactRealCellSelection<Base>
    let indices: ArraySlice<Int>
    public var startIndex: Int { indices.startIndex }
    public var endIndex: Int { indices.endIndex }
    public subscript(index: Int) -> Element { original.cells[indices[index]] }
}
