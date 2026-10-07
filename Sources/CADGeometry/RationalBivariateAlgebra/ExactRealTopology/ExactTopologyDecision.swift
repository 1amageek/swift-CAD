#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

struct ExactTopologyDecision<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
 let cell: ExactRealCellID<Base>
 let children: Range<Int>
 var truth: Bool
}
