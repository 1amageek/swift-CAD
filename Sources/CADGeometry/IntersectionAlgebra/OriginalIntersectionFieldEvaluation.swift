/// Exact original-coordinate substitution; whole-cell proof belongs to the projection owner.
package enum OriginalIntersectionFieldEvaluation {
    package static func specialized<B: RationalAlgebraAdmitting>(
        _ original: ExactIntersectionPolynomial, at coordinate: Int, context: OriginalSingularFieldContext, coordinates: [OriginalSingularFieldElement],
        maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldPolynomial? {
        guard coordinate >= 0, coordinate < original.variableCount, coordinates.count == coordinate else {
            throw rationalAlgebraFailure("Original field substitution requires the preceding coordinate prefix.")
        }
        try validate(context: context, coordinates: coordinates, usage: &usage)
        let terms = try original.orderedTerms(usage: &usage)
        var degree = 0
        for term in terms {
            try intersectionAlgebraStep(&usage)
            for later in (coordinate + 1)..<original.variableCount {
                if try term.key.exponent(at: later) != 0 { return nil }
            }
            degree = max(degree, try term.key.exponent(at: coordinate))
        }
        let count = try rationalAlgebraCount(degree, 1)
        let zero = try OriginalSingularFieldElement.constant(.zero, in: context,
            maximumDepth: maximumDepth, usage: &usage)
        try RationalAlgebraStorage.retain(count, of: OriginalSingularFieldElement.self, usage: &usage)
        var coefficients = Array(repeating: zero, count: count)
        for term in terms {
            var value = try OriginalSingularFieldElement.constant(term.value, in: context,
                maximumDepth: maximumDepth, usage: &usage)
            for preceding in 0..<coordinate {
                value = try value.multiplied(by: power(coordinates[preceding],
                    exponent: term.key.exponent(at: preceding), maximumDepth: maximumDepth, usage: &usage),
                    maximumDepth: maximumDepth, usage: &usage)
            }
            let index = try term.key.exponent(at: coordinate)
            coefficients[index] = try coefficients[index].adding(value,
                maximumDepth: maximumDepth, usage: &usage)
        }
        return try OriginalSingularFieldPolynomial(context: context,
            coefficients: coefficients, maximumDepth: maximumDepth, usage: &usage)
    }

    package static func evaluated<B: RationalAlgebraAdmitting>(_ polynomial: ExactIntersectionPolynomial,
        context: OriginalSingularFieldContext, coordinates: [OriginalSingularFieldElement], maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldElement {
        guard coordinates.count == polynomial.variableCount else {
            throw rationalAlgebraFailure("Original field evaluation requires every source coordinate.")
        }
        try validate(context: context, coordinates: coordinates, usage: &usage)
        var result = try OriginalSingularFieldElement.constant(.zero, in: context,
            maximumDepth: maximumDepth, usage: &usage)
        for term in try polynomial.orderedTerms(usage: &usage) {
            var value = try OriginalSingularFieldElement.constant(term.value, in: context,
                maximumDepth: maximumDepth, usage: &usage)
            for coordinate in coordinates.indices {
                value = try value.multiplied(by: power(coordinates[coordinate],
                    exponent: term.key.exponent(at: coordinate), maximumDepth: maximumDepth, usage: &usage),
                    maximumDepth: maximumDepth, usage: &usage)
            }
            result = try result.adding(value, maximumDepth: maximumDepth, usage: &usage)
        }
        return result
    }

    package static func power<B: RationalAlgebraAdmitting>(_ value: OriginalSingularFieldElement,
        exponent: Int, maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldElement {
        guard exponent >= 0 else { throw rationalAlgebraFailure("Original field powers require nonnegative exponents.") }
        var result = try OriginalSingularFieldElement.constant(.one, in: value.context,
            maximumDepth: maximumDepth, usage: &usage)
        var exponent = exponent, factor = value
        while exponent > 0 {
            try intersectionAlgebraStep(&usage)
            if exponent & 1 != 0 {
                result = try result.multiplied(by: factor, maximumDepth: maximumDepth, usage: &usage)
            }
            exponent /= 2
            if exponent > 0 {
                factor = try factor.multiplied(by: factor, maximumDepth: maximumDepth, usage: &usage)
            }
        }
        return result
    }

    private static func validate<B: RationalAlgebraAdmitting>(context: OriginalSingularFieldContext,
        coordinates: [OriginalSingularFieldElement], usage: inout B) throws {
        for coordinate in coordinates {
            try intersectionAlgebraStep(&usage)
            guard coordinate.context === context else {
                throw rationalAlgebraFailure("Original field coordinates do not share their retained owner.")
            }
        }
    }
}
