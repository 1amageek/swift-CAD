/// A geometric polynomial retaining actual original ordered-field coefficients.
package struct OriginalOrderedIntersectionPolynomial: Sendable {
    package struct Term: Sendable {
        package let power: ExactIntersectionPolynomial.Power
        package let coefficient: OriginalSingularFieldElement
        package let inheritedParameterDepth: Int
        package let inheritedCoefficientDepth: Int
        package init(power: ExactIntersectionPolynomial.Power, coefficient: OriginalSingularFieldElement,
            inheritedParameterDepth: Int = 0, inheritedCoefficientDepth: Int = 0) {
            self.power = power; self.coefficient = coefficient
            self.inheritedParameterDepth = max(inheritedParameterDepth, coefficient.context.depth)
            self.inheritedCoefficientDepth = max(inheritedCoefficientDepth, coefficient.context.coefficientDepth)
        }
    }
    package let variableCount: Int
    package let terms: [Term]
    package let inheritedParameterDepth: Int
    package let inheritedCoefficientDepth: Int

    package init<B: ExactScalarAdmission & ~Copyable>(variableCount: Int, terms: [Term],
        maximumDepth: Int, maximumCoefficientDepth: Int,
        inheritedParameterDepth: Int = 0, inheritedCoefficientDepth: Int = 0, usage: inout B) throws {
        try intersectionAlgebraStep(&usage)
        guard variableCount > 0, maximumDepth >= 0, (0...32).contains(maximumCoefficientDepth),
            inheritedParameterDepth >= 0, inheritedParameterDepth <= maximumDepth,
            inheritedCoefficientDepth >= 0, inheritedCoefficientDepth <= maximumCoefficientDepth else {
            throw rationalAlgebraFailure("An ordered source polynomial requires its geometric ring and independent depths.")
        }
        try RationalAlgebraStorage.retain(terms.count, of: Term.self, usage: &usage)
        var parameterDepth = inheritedParameterDepth, coefficientDepth = inheritedCoefficientDepth
        var retained: [Term] = []; retained.reserveCapacity(terms.count)
        for term in terms {
            try intersectionAlgebraStep(&usage)
            try term.power.validate(variableCount: variableCount, usage: &usage)
            guard term.inheritedParameterDepth >= 0, term.inheritedParameterDepth <= maximumDepth,
                term.inheritedCoefficientDepth >= 0, term.inheritedCoefficientDepth <= maximumCoefficientDepth else {
                throw rationalAlgebraFailure("An ordered polynomial cannot reset its original coefficient source depth.")
            }
            parameterDepth = max(parameterDepth, term.inheritedParameterDepth)
            coefficientDepth = max(coefficientDepth, term.inheritedCoefficientDepth)
            let available=try rationalAlgebraCount(term.coefficient.context.depth,maximumDepth-term.inheritedParameterDepth)
            let source=try intersectionSourceCalculation(originalParameterDepth:term.coefficient.context.depth,
                originalCoefficientDepth:term.coefficient.context.coefficientDepth,
                inheritedParameterDepth:term.inheritedParameterDepth,inheritedCoefficientDepth:term.inheritedCoefficientDepth,
                maximumDepth:maximumDepth,maximumCoefficientDepth:maximumCoefficientDepth,usage:&usage) { a in
                try term.coefficient.sign(maximumDepth:available,usage:&a)
            }
            let sign=source.value
            parameterDepth=max(parameterDepth,source.parameterDepth)
            coefficientDepth=max(coefficientDepth,source.coefficientDepth)
            if sign != .zero {
                retained.append(.init(power: term.power, coefficient: term.coefficient,
                    inheritedParameterDepth: source.parameterDepth, inheritedCoefficientDepth: source.coefficientDepth))
            }
        }
        self.variableCount = variableCount; self.terms = retained
        self.inheritedParameterDepth = parameterDepth; self.inheritedCoefficientDepth = coefficientDepth
    }

    package static func embedding<B: ExactScalarAdmission & ~Copyable>(_ original: OriginalSingularFieldPlanePolynomial,
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

    package func differentiated<B: ExactScalarAdmission & ~Copyable>(at axis: Int,
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
            guard term.inheritedParameterDepth <= maximumDepth, term.inheritedCoefficientDepth <= maximumCoefficientDepth else {
                throw rationalAlgebraFailure("An ordered derivative cannot reset its source admission depth.")
            }
            let available=try rationalAlgebraCount(term.coefficient.context.depth,maximumDepth-term.inheritedParameterDepth)
            let source=try intersectionSourceCalculation(originalParameterDepth:term.coefficient.context.depth,
                originalCoefficientDepth:term.coefficient.context.coefficientDepth,
                inheritedParameterDepth:term.inheritedParameterDepth,inheritedCoefficientDepth:term.inheritedCoefficientDepth,
                maximumDepth:maximumDepth,maximumCoefficientDepth:maximumCoefficientDepth,usage:&usage) { a in
                let factor=try OriginalSingularFieldElement.constant(.natural(degree,usage:&a),
                    in:term.coefficient.context,maximumDepth:available,usage:&a)
                return try term.coefficient.multiplied(by:factor,maximumDepth:available,usage:&a)
            }
            let scaled=source.value
            let power = try term.power.quotient(by: unit, variableCount: variableCount, usage: &usage)
            result.append(.init(power: power, coefficient: scaled,
                inheritedParameterDepth: source.parameterDepth, inheritedCoefficientDepth: source.coefficientDepth))
        }
        return try Self(variableCount: variableCount, terms: result, maximumDepth: maximumDepth,
            maximumCoefficientDepth: maximumCoefficientDepth, inheritedParameterDepth: inheritedParameterDepth,
            inheritedCoefficientDepth: inheritedCoefficientDepth, usage: &usage)
    }
}
