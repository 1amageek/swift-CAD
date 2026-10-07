#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

public struct ExactRealCellDefinitionStep<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
 public let parent: ExactRealCellID<Base>
 public let cell: ExactRealCellID<Base>
 public let axis: Int
 public let section: ExactRealCellBoundaryRoot<Base>?
 public let lower: ExactRealCellBoundaryRoot<Base>?
 public let upper: ExactRealCellBoundaryRoot<Base>?
}
