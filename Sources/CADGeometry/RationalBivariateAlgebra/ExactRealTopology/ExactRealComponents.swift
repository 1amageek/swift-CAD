#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

public struct ExactRealComponents<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
 public let incidence: ExactRealIncidence<Base>
 public let members: [ExactRealCellID<Base>]
 public let memberRanges: [Range<Int>]
 public let witnesses: [Int]
 public let witnessRanges: [Range<Int>]
 public var count: Int { memberRanges.count }
 public let depth: ExactScalarDepth
}
