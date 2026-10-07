#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

public protocol ExactRealCellSelecting<Base>: Sendable {
 associatedtype Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting where Base.Source == Base.Value
 func select<A: ExactScalarAdmission & ~Copyable>(_ partition: borrowing ExactRealCellPartition<Base>,
  matching predicate: borrowing ExactRealCellPredicate<Base>, using admission: inout A) throws(ExactRealCellFailure) -> ExactRealCellSelection<Base>
}
