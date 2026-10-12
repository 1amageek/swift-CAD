#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

public struct ExactRealAttachment<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
 public let source: ExactRealCellID<Base>
 public let target: ExactRealCellID<Base>
 public let closure: ExactRealClosure<Base>
 public let region: ExactRealTopologyRegion<Base>
 public let piece: ExactRealCellID<Base>
}
