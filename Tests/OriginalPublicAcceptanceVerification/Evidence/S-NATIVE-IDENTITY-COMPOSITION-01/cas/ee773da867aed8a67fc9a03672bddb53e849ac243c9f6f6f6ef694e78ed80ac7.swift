#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

public protocol ExactRealCellProducing<Base>: Sendable {
 associatedtype Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting where Base.Source == Base.Value
 func decompose<A: ExactScalarAdmission & ~Copyable>(_ source: borrowing ExactRealCellSource<Base>,
  limits: ExactRealCellLimits, using admission: inout A) throws(ExactRealCellFailure) -> ExactRealCellPartition<Base>
}
