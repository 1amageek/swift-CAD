#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

public struct ExactRealCellSource<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    public typealias Field = ExactAlgebraicScalarDomain<Base>
    let owner: ExactRealCellSourceStorage<Base>
    public var polynomials: [ExactPolynomial<Field>] { owner.laws }
    public var domains: [ExactRealRootInterval<Field.Value>] { owner.domains }
    public var variableCount: Int { owner.context.polynomials.variableCount }
    public var depth: ExactScalarDepth { owner.depth }
    init(owner: ExactRealCellSourceStorage<Base>) { self.owner = owner }
}
