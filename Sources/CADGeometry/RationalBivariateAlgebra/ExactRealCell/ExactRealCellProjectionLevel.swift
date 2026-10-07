#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

struct ExactRealCellProjectionLevel<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    typealias Polynomial = ExactPolynomial<ExactAlgebraicScalarDomain<Base>>
    let axis: Int
    let cutLawCount: Int
    let laws: [Polynomial]
    let coefficients: [[Polynomial]]
    let witnesses: [ExactRealCellProjectionWitness<Base>]
}
