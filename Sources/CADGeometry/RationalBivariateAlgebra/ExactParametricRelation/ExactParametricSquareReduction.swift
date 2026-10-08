#if L5_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
#endif

/// Exact ordered-field proof that one equality is equivalent to affine factors.
public struct ExactParametricSquareReduction<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    public typealias Field = ExactAlgebraicScalarDomain<Base>
    public let equationIndex: Int
    public let equation: ExactPolynomial<Field>
    public let negated: Bool
    public let positiveWeights: [Field.Value]
    public let factors: [ExactPolynomial<Field>]
    public let reconstructedIdentity: ExactPolynomial<Field>
    public let divisions: [ExactParametricConstraintDivision<Base>]
}
