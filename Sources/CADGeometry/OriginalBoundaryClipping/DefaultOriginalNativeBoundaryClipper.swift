import CADCore

/// Refines every selected original Native parameter cell against the issued original boundaries.
public struct DefaultOriginalNativeBoundaryClipper: OriginalNativeBoundaryClipping {
    public init() {}
    public func clip(_ boundary: OriginalNativeBoundaryDomain, selection: OriginalNativeBoundaryDomain.Selection,
        maximumDepth: Int, maximumCoefficientDepth: Int,
        using admission: inout OriginalQueryExecution) throws -> OriginalClippedNativeParameters {
        try intersectionAlgebraStep(&admission)
        guard maximumDepth >= 0, (0...32).contains(maximumCoefficientDepth) else {
            throw rationalAlgebraFailure("Original boundary clipping requires independent nonnegative caller depths.")
        }
        let source = try OriginalBoundarySourceCover(boundary.source, maximumDepth: maximumDepth,
            maximumCoefficientDepth: maximumCoefficientDepth, usage: &admission)
        var compiler = OriginalBoundaryBooleanCompiler()
        // Preserve original source equations and nonzero denominator laws even when
        // derivative-closed cell conditions already imply their selected signs.
        for law in source.laws {
            try intersectionAlgebraStep(&admission)
            _ = try compiler.atom(law, .zero, usage: &admission)
        }
        var rawNodes: [Int] = []
        try RationalAlgebraStorage.retain(source.conditions.count, of: Int.self, usage: &admission)
        var rawUnion = try compiler.node(.literal(false), usage: &admission)
        for (index, condition) in source.conditions.enumerated() {
            try intersectionAlgebraStep(&admission)
            let cell = try compiler.condition(condition, usage: &admission)
            let originalSystem = try compiler.sourceSystem(source.systems[index], usage: &admission)
            let node = try compiler.conjunction(cell, originalSystem, usage: &admission)
            rawNodes.append(node); rawUnion = try compiler.disjunction(rawUnion, node, usage: &admission)
        }
        let trim = try compiler.boundary(boundary, selection: selection, usage: &admission)
        let selected = try compiler.conjunction(rawUnion, trim, usage: &admission)
        let program = try OriginalPolynomialPredicate(polynomialCount: compiler.laws.count,
            instructions: compiler.instructions(selected, usage: &admission), usage: &admission)
        try RationalAlgebraStorage.retain(compiler.laws.count, of: OriginalRationalPolynomial.self, usage: &admission)
        var laws: [OriginalRationalPolynomial] = []; laws.reserveCapacity(compiler.laws.count)
        for law in compiler.laws {
            try intersectionAlgebraStep(&admission)
            let terms = try law.orderedTerms(usage: &admission)
            try RationalAlgebraStorage.retain(terms.count, of: OriginalRationalPolynomial.Term.self, usage: &admission)
            var original: [OriginalRationalPolynomial.Term] = []; original.reserveCapacity(terms.count)
            for (power, coefficient) in terms {
            try intersectionAlgebraStep(&admission)
                try RationalAlgebraStorage.retain(boundary.source.variableCount, of: Int.self, usage: &admission)
                var powers: [Int] = []; powers.reserveCapacity(boundary.source.variableCount)
                for axis in 0..<boundary.source.variableCount {
                    try intersectionAlgebraStep(&admission)
                    powers.append(try power.exponent(at: axis))
                }
                original.append(.init(coefficient: coefficient, powers: powers))
            }
            let retained = try OriginalRationalPolynomial(variableCount: boundary.source.variableCount,
                terms: original, usage: &admission)
            guard try retained.original.matches(law, usage: &admission) else {
                throw rationalAlgebraFailure("Boundary composition changed an original source law.")
            }
            laws.append(retained)
        }
        let input = try OriginalPolynomialRelation(variableCount: boundary.source.variableCount,
            polynomials: laws, predicate: program, domains: boundary.source.domains, usage: &admission)
        let baseline = OriginalBoundaryAdmission(parameterDepth: source.parameterDepth, coefficientDepth: source.coefficientDepth)
        let result = try baseline.withScope(maximumDepth: maximumDepth,
            maximumCoefficientDepth: maximumCoefficientDepth, usage: &admission) { admission in
            try DefaultOriginalPolynomialRelationResolver().decompose(input,
                maximumDepth: maximumDepth - baseline.parameterDepth,
                maximumCoefficientDepth: maximumCoefficientDepth - baseline.coefficientDepth, usage: &admission)
        }
        return try OriginalClippedNativeParameters(boundary: boundary, selection: selection, relation: result,
            source: source, rawNodes: rawNodes, compiler: compiler, baseline: baseline, usage: &admission)
    }
}
