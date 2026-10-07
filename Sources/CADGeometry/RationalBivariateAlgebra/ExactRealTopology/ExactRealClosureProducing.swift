#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

public protocol ExactRealClosureProducing<Base>: Sendable {
 associatedtype Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting where Base.Source == Base.Value
 func closure<A: ExactScalarAdmission & ~Copyable>(of cell: ExactRealCellID<Base>, in partition: borrowing ExactRealCellPartition<Base>,
  strategy: ExactRealClosureStrategy, limits: ExactRealTopologyLimits, using admission: inout A) throws(ExactRealTopologyFailure) -> ExactRealClosure<Base>
}
