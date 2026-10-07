#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

struct ExactRealCellRecord<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
 let sample: ExactRealCellSample<Base>
 let parent: Int
 let branch: Int
 let dimension: Int
 let signs: [ExactSign]
 var stack: Int
}
