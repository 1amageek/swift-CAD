#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

public protocol ExactRealCellQuerying<Base>: Sendable {
 associatedtype Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting where Base.Source == Base.Value
 func sample<A: ExactScalarAdmission & ~Copyable>(of cell: ExactRealCellID<Base>, in partition: borrowing ExactRealCellPartition<Base>,
  using admission: inout A) throws(ExactRealCellFailure) -> ExactRealCellSample<Base>
 func condition<A: ExactScalarAdmission & ~Copyable>(of cell: ExactRealCellID<Base>, in partition: borrowing ExactRealCellPartition<Base>,
  using admission: inout A) throws(ExactRealCellFailure) -> ExactRealCellCondition<Base>
 func point<A: ExactScalarAdmission & ~Copyable>(field: ExactAlgebraicScalarDomain<Base>, coordinates: [ExactAlgebraicScalar<Base>],
  using admission: inout A) throws(ExactRealCellFailure) -> ExactRealCellSample<Base>
 func locate<A: ExactScalarAdmission & ~Copyable>(_ point: borrowing ExactRealCellSample<Base>, in partition: borrowing ExactRealCellPartition<Base>,
  limits: ExactRealRootLimits, using admission: inout A) throws(ExactRealCellFailure) -> ExactRealCellID<Base>?
 func locatePrefix<A: ExactScalarAdmission & ~Copyable>(_ point: borrowing ExactRealCellSample<Base>, in partition: borrowing ExactRealCellPartition<Base>,
  limits: ExactRealRootLimits, using admission: inout A) throws(ExactRealCellFailure) -> ExactRealCellID<Base>?
 func contains<A: ExactScalarAdmission & ~Copyable>(_ point: borrowing ExactRealCellSample<Base>, in condition: borrowing ExactRealCellCondition<Base>,
  limits: ExactRealRootLimits, using admission: inout A) throws(ExactRealCellFailure) -> Bool
}
