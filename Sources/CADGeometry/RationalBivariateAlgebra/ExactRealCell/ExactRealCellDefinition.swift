#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

public struct ExactRealCellDefinition<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
 public let partition: ExactRealCellPartition<Base>
 public let cell: ExactRealCellID<Base>
 public let coefficientField: ExactAlgebraicScalarDomain<Base>
 public let steps: [ExactRealCellDefinitionStep<Base>]
 public var coordinateCount: Int { steps.count }
 public let depth: ExactScalarDepth
}
