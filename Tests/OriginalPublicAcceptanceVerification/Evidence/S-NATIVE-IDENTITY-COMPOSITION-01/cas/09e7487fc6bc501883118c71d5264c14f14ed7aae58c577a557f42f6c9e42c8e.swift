#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

struct ExactTopologyFormula<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting> where Base.Source == Base.Value {
 typealias Field = ExactAlgebraicScalarDomain<Base>
 typealias Polynomial = ExactPolynomial<Field>
 let field: Field
 var polynomials: ExactPolynomialDomain<Field>
 var atoms: [Polynomial] = []
 var instructions: [ExactRealCellInstruction] = []
 let freeCount: Int
 var conjunctionEnd: Int? = nil
 var reductions: [ExactRealTopologyReduction<Base>] = []
 var eliminations: [ExactRealTopologyElimination<Base>] = []
 var quantifiers: [Bool]
}
