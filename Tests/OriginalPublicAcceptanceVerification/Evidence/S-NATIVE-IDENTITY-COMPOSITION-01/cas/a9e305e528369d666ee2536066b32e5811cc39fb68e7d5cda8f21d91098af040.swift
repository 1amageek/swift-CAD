#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

public struct ExactRealClosure<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
 public let definition: ExactRealCellDefinition<Base>
 public let factors: [ExactRealTopologyFactor<Base>]
 public let proof: ExactRealClosureProof
 public let region: ExactRealTopologyRegion<Base>
 public let applicability: ExactRealTopologyRegion<Base>?
 public let depth: ExactScalarDepth
}
