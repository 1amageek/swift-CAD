#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

public protocol ExactRealCellDescribing<Base>: Sendable {
 associatedtype Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting where Base.Source == Base.Value
 func projectionEvidence<A: ExactScalarAdmission & ~Copyable>(forAxis axis: Int, in partition: borrowing ExactRealCellPartition<Base>,
  using admission: inout A) throws(ExactRealCellFailure) -> ExactRealCellProjectionEvidence<Base>
 func stackEvidence<A: ExactScalarAdmission & ~Copyable>(over parent: ExactRealCellID<Base>, in partition: borrowing ExactRealCellPartition<Base>,
  using admission: inout A) throws(ExactRealCellFailure) -> ExactRealCellStackEvidence<Base>
 func coefficientField<A: ExactScalarAdmission & ~Copyable>(of source: borrowing ExactRealCellSource<Base>, using admission: inout A) throws(ExactRealCellFailure) -> ExactAlgebraicScalarDomain<Base>
 func definition<A: ExactScalarAdmission & ~Copyable>(of cell: ExactRealCellID<Base>, in partition: borrowing ExactRealCellPartition<Base>, using admission: inout A) throws(ExactRealCellFailure) -> ExactRealCellDefinition<Base>
 func signInvariant<A: ExactScalarAdmission & ~Copyable>(for polynomial: borrowing ExactPolynomial<ExactAlgebraicScalarDomain<Base>>,
  in partition: borrowing ExactRealCellPartition<Base>, using admission: inout A) throws(ExactRealCellFailure) -> ExactRealCellSignInvariant<Base>?
}
