#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

public struct ExactRealIncidence<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
 public let selection: ExactRealCellSelection<Base>
 public let closures: [ExactRealClosure<Base>]
 public let pairs: [ExactRealIncidencePair<Base>]
 public let attachments: [ExactRealAttachment<Base>]
 public let depth: ExactScalarDepth
}
