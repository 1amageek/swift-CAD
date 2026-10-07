#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

struct ExactRealCellStack<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
 typealias Field = ExactAlgebraicScalarDomain<Base>
 let axis: Int
 let parent: Int
 let rootSet: ExactRealRootSet<Field>
 let specialized: [ExactRealRootSource<Field>]
 let coefficientSigns: [[ExactSign]]
 let activeLawIndices: [Int]
 let children: [Int]
}
