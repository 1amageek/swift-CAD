#if L5_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
#endif

/// Parameter prefixes precede both auxiliary suffixes in the combined solver source.
public struct ExactParametricGraphRelationSource<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    public let depth: ExactScalarDepth
    public let kind: ExactParametricRelationKind
    public let first: ExactParametricGraph<Base>
    public let second: ExactParametricGraph<Base>
    public let firstCoordinates: [Int]
    public let secondCoordinates: [Int]
    /// -1 denotes a position law not referenced by the solver predicate.
    public let firstLawIndices: [Int]
    public let secondLawIndices: [Int]
    public let equationIndices: Range<Int>
    public let rawEquations: [ExactPolynomial<ExactAlgebraicScalarDomain<Base>>]
    public let guardRemainders: [ExactParametricGuardRemainder<Base>]
    public let guardDivisions: [ExactParametricGuardDivision<Base>]
    public let predicate: ExactRealCellPredicate<Base>
    public var parameterCount: Int { first.parameterCount + second.parameterCount }
    init(kind: ExactParametricRelationKind, first: ExactParametricGraph<Base>, second: ExactParametricGraph<Base>,
        firstCoordinates: [Int], secondCoordinates: [Int], firstLawIndices: [Int], secondLawIndices: [Int],
        equationIndices: Range<Int>, rawEquations: [ExactPolynomial<ExactAlgebraicScalarDomain<Base>>],
        guardDivisions: [ExactParametricGuardDivision<Base>], guardRemainders: [ExactParametricGuardRemainder<Base>], predicate: ExactRealCellPredicate<Base>, depth: ExactScalarDepth) {
        self.depth = depth; self.kind = kind; self.first = first; self.second = second
        self.firstCoordinates = firstCoordinates; self.secondCoordinates = secondCoordinates
        self.firstLawIndices = firstLawIndices; self.secondLawIndices = secondLawIndices; self.equationIndices = equationIndices
        self.rawEquations = rawEquations; self.guardDivisions = guardDivisions; self.guardRemainders = guardRemainders; self.predicate = predicate
    }
}
