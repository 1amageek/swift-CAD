#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

public protocol ExactRealCellTraversing<Base>: Sendable {
 associatedtype Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting where Base.Source == Base.Value
 func root<A: ExactScalarAdmission & ~Copyable>(in partition: borrowing ExactRealCellPartition<Base>, using admission: inout A) throws(ExactRealCellFailure) -> ExactRealCellID<Base>?
 func children<A: ExactScalarAdmission & ~Copyable>(of cell: ExactRealCellID<Base>, in partition: borrowing ExactRealCellPartition<Base>, using admission: inout A) throws(ExactRealCellFailure) -> ExactRealCellView<Base>
}
