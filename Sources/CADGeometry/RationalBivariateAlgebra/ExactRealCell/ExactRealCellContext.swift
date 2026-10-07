#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

final class ExactRealCellContext<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    typealias Field = ExactAlgebraicScalarDomain<Base>
    let field: Field
    let polynomials: ExactPolynomialDomain<Field>
    let depth: ExactScalarDepth
    init(field: Field, polynomials: ExactPolynomialDomain<Field>, depth: ExactScalarDepth) {
        self.field = field; self.polynomials = polynomials; self.depth = depth
    }
}
