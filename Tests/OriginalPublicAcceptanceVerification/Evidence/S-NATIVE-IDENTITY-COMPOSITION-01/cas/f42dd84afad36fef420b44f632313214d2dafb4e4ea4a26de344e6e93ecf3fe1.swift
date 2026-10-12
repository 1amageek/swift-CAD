#if L5_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
#endif

/// Retains the original maps and the full compiled equality/denominator predicate.
public struct ExactParametricRelationSource<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    public let kind: ExactParametricRelationKind
    public let first: ExactParametricMap<Base>
    public let second: ExactParametricMap<Base>
    public let rawEquations: [ExactPolynomial<ExactAlgebraicScalarDomain<Base>>]
    public let guardDivisions: [ExactParametricGuardDivision<Base>]
    public let squareReduction: ExactParametricSquareReduction<Base>?
    public let predicate: ExactRealCellPredicate<Base>
    public var firstParameters: Range<Int> { 0..<first.parameterCount }
    public var secondParameters: Range<Int> { first.parameterCount..<predicate.source.variableCount }
    init(kind: ExactParametricRelationKind, first: ExactParametricMap<Base>, second: ExactParametricMap<Base>,
         rawEquations: [ExactPolynomial<ExactAlgebraicScalarDomain<Base>>],
         guardDivisions: [ExactParametricGuardDivision<Base>], predicate: ExactRealCellPredicate<Base>,
         squareReduction: ExactParametricSquareReduction<Base>? = nil) {
        self.rawEquations = rawEquations; self.guardDivisions = guardDivisions
        self.squareReduction = squareReduction
        self.kind = kind; self.first = first; self.second = second; self.predicate = predicate
    }
}
