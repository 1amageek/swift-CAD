/// A geometric polynomial retaining actual original ordered-field coefficients.
package struct OriginalOrderedIntersectionPolynomial: Sendable {
    package struct Term: Sendable {
        package let power: ExactIntersectionPolynomial.Power
        package let coefficient: OriginalSingularFieldElement
    }
    package let variableCount: Int
    package let terms: [Term]

    package init<B: RationalAlgebraAdmitting>(variableCount: Int, terms: [Term],
        maximumDepth: Int, maximumCoefficientDepth: Int, usage: inout B) throws {
        try intersectionAlgebraStep(&usage)
        guard variableCount > 0, maximumDepth >= 0, (0...32).contains(maximumCoefficientDepth) else {
            throw rationalAlgebraFailure("An ordered source polynomial requires its geometric ring and independent depths.")
        }
        try RationalAlgebraStorage.retain(terms.count, of: Term.self, usage: &usage)
        var retained: [Term] = []; retained.reserveCapacity(terms.count)
        for term in terms {
            try intersectionAlgebraStep(&usage)
            try term.power.validate(variableCount: variableCount, usage: &usage)
            guard term.coefficient.context.depth <= maximumDepth,
                term.coefficient.context.coefficientDepth <= maximumCoefficientDepth else {
                throw rationalAlgebraFailure("An ordered polynomial cannot reset its original coefficient source depth.")
            }
            if try term.coefficient.sign(maximumDepth: maximumDepth, usage: &usage) != .zero { retained.append(term) }
        }
        self.variableCount = variableCount; self.terms = retained
    }

    package static func embedding<B: RationalAlgebraAdmitting>(_ original: OriginalSingularFieldPlanePolynomial,
        variableCount: Int, uCoordinate: Int, vCoordinate: Int,
        maximumDepth: Int, maximumCoefficientDepth: Int, usage: inout B) throws -> Self {
        guard uCoordinate >= 0, vCoordinate >= 0, uCoordinate < variableCount,
            vCoordinate < variableCount, uCoordinate != vCoordinate else {
            throw rationalAlgebraFailure("Original field source parameters require distinct geometric coordinates.")
        }
        try RationalAlgebraStorage.retain(original.coefficients.count, of: Term.self, usage: &usage)
        var terms: [Term] = []; terms.reserveCapacity(original.coefficients.count)
        try RationalAlgebraStorage.retain(variableCount, of: Int.self, usage: &usage)
        var powers = Array(repeating: 0, count: variableCount)
        for (power, coefficient) in try original.orderedTerms(usage: &usage) {
            try intersectionAlgebraStep(&usage)
            powers[uCoordinate] = power.u; powers[vCoordinate] = power.v
            terms.append(.init(power: try .init(powers, variableCount: variableCount, usage: &usage), coefficient: coefficient))
        }
        return try Self(variableCount: variableCount, terms: terms,
            maximumDepth: maximumDepth, maximumCoefficientDepth: maximumCoefficientDepth, usage: &usage)
    }

    package func differentiated<B: RationalAlgebraAdmitting>(at axis: Int,
        maximumDepth: Int, maximumCoefficientDepth: Int, usage: inout B) throws -> Self {
        guard axis >= 0, axis < variableCount else {
            throw rationalAlgebraFailure("An ordered derivative requires its original geometric coordinate.")
        }
        let unit = try ExactIntersectionPolynomial.Power.coordinate(at: axis, variableCount: variableCount, usage: &usage)
        try RationalAlgebraStorage.retain(terms.count, of: Term.self, usage: &usage)
        var result: [Term] = []; result.reserveCapacity(terms.count)
        for term in terms {
            try intersectionAlgebraStep(&usage)
            let degree = try term.power.exponent(at: axis)
            if degree == 0 { continue }
            let factor = try OriginalSingularFieldElement.constant(.natural(degree, usage: &usage),
                in: term.coefficient.context, maximumDepth: maximumDepth, usage: &usage)
            let power = try term.power.quotient(by: unit, variableCount: variableCount, usage: &usage)
            result.append(.init(power: power, coefficient: try term.coefficient.multiplied(by: factor,
                maximumDepth: maximumDepth, usage: &usage)))
        }
        return try Self(variableCount: variableCount, terms: result, maximumDepth: maximumDepth,
            maximumCoefficientDepth: maximumCoefficientDepth, usage: &usage)
    }
}
