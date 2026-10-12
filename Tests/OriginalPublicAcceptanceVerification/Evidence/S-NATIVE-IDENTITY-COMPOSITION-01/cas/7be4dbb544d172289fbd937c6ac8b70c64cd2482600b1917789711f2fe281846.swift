#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

final class ExactRealCellSourceStorage<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    typealias Field = ExactAlgebraicScalarDomain<Base>
    let context: ExactRealCellContext<Base>
    let laws: [ExactPolynomial<Field>]
    let domains: [ExactRealRootInterval<Field.Value>]
    let depth: ExactScalarDepth
    init(context: ExactRealCellContext<Base>, laws: [ExactPolynomial<Field>],
        domains: [ExactRealRootInterval<Field.Value>], depth: ExactScalarDepth) {
        self.context = context; self.laws = laws; self.domains = domains; self.depth = depth
    }
}
