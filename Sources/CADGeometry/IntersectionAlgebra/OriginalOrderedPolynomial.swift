/// An original geometric law with exact retained scalar coefficients.
public struct OriginalOrderedPolynomial: Sendable {
    public struct Term: Sendable {
        public let coefficient: OriginalAlgebraicCoordinate
        public let powers: [Int]
        public init(coefficient: OriginalAlgebraicCoordinate, powers: [Int]) {
            self.coefficient = coefficient; self.powers = powers
        }
    }
    public let variableCount: Int
    package let original: OriginalOrderedIntersectionPolynomial

    public init(variableCount: Int, terms: [Term], maximumDepth: Int,
        maximumCoefficientDepth: Int, usage: OriginalRelationUsage) throws {
        var admission = usage
        guard (1...4).contains(variableCount) else {
            throw rationalAlgebraFailure("A public ordered law requires its complete original geometric ring.")
        }
        try RationalAlgebraStorage.retain(terms.count, of: OriginalOrderedIntersectionPolynomial.Term.self, usage: &admission)
        var retained: [OriginalOrderedIntersectionPolynomial.Term] = []; retained.reserveCapacity(terms.count)
        for term in terms {
            try intersectionAlgebraStep(&admission)
            retained.append(.init(power: try .init(term.powers, variableCount: variableCount, usage: &admission),
                coefficient: term.coefficient.original, inheritedParameterDepth: term.coefficient.inheritedDepth,
                inheritedCoefficientDepth: term.coefficient.inheritedCoefficientDepth))
        }
        original = try .init(variableCount: variableCount, terms: retained, maximumDepth: maximumDepth,
            maximumCoefficientDepth: maximumCoefficientDepth, usage: &admission)
        self.variableCount = variableCount
    }

    package init(original: OriginalOrderedIntersectionPolynomial) {
        self.original = original; variableCount = original.variableCount
    }

    public func differentiated(at coordinate: Int, maximumDepth: Int,
        maximumCoefficientDepth: Int, usage: OriginalRelationUsage) throws -> Self {
        var admission = usage
        return try .init(original: original.differentiated(at: coordinate, maximumDepth: maximumDepth,
            maximumCoefficientDepth: maximumCoefficientDepth, usage: &admission))
    }
}
