#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

public struct ExactRealIncidencePair<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
 public let source: ExactRealCellID<Base>
 public let target: ExactRealCellID<Base>
 /// Nil only for the identity-based diagonal containment certificate.
 public let region: ExactRealTopologyRegion<Base>?
 public let attachments: Range<Int>
}
