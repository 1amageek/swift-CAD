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
        if case .rational = context.source {
            let prefix = try rationalCoordinates(context: context, coordinates: coordinates, usage: &usage)
            try RationalAlgebraStorage.retain(count, of: ExactRationalCoefficient.self, usage: &usage)
            var coefficients = Array(repeating: ExactRationalCoefficient.zero, count: count)
            for term in terms {
                var value = term.value
                for preceding in 0..<coordinate {
                    try intersectionAlgebraStep(&usage)
                    let exponent = try term.key.exponent(at: preceding)
                    if exponent == 0 { continue }
                    value = try value.multiplied(by: rationalPower(prefix[preceding], exponent: exponent, usage: &usage), usage: &usage)
                }
                let index = try term.key.exponent(at: coordinate)
                coefficients[index] = try coefficients[index].adding(value, usage: &usage)
            }
            try RationalAlgebraStorage.retain(count, of: OriginalSingularFieldElement.self, usage: &usage)
            var values: [OriginalSingularFieldElement] = []; values.reserveCapacity(count)
            for coefficient in coefficients {
                values.append(try .constant(coefficient, in: context, maximumDepth: maximumDepth, usage: &usage))
            }
            return try OriginalSingularFieldPolynomial(context: context, coefficients: values, maximumDepth: maximumDepth, usage: &usage)
        }
        let zero = try OriginalSingularFieldElement.constant(.zero, in: context,
            maximumDepth: maximumDepth, usage: &usage)
        try RationalAlgebraStorage.retain(count, of: OriginalSingularFieldElement.self, usage: &usage)
        var coefficients = Array(repeating: zero, count: count)
        for term in terms {
            var value = try OriginalSingularFieldElement.constant(term.value, in: context,
                maximumDepth: maximumDepth, usage: &usage)
            for preceding in 0..<coordinate {
                try intersectionAlgebraStep(&usage)
                let exponent = try term.key.exponent(at: preceding)
                if exponent == 0 { continue }
                value = try value.multiplied(by: power(coordinates[preceding],
                    exponent: exponent, maximumDepth: maximumDepth, usage: &usage),
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
        if case .rational = context.source {
            let prefix = try rationalCoordinates(context: context, coordinates: coordinates, usage: &usage)
            var result = ExactRationalCoefficient.zero
            for term in try polynomial.orderedTerms(usage: &usage) {
                var value = term.value
                for coordinate in coordinates.indices {
                    try intersectionAlgebraStep(&usage)
                    let exponent = try term.key.exponent(at: coordinate)
                    if exponent == 0 { continue }
                    value = try value.multiplied(by: rationalPower(prefix[coordinate], exponent: exponent, usage: &usage), usage: &usage)
                }
                result = try result.adding(value, usage: &usage)
            }
            return try .constant(result, in: context, maximumDepth: maximumDepth, usage: &usage)
        }
        var result = try OriginalSingularFieldElement.constant(.zero, in: context,
            maximumDepth: maximumDepth, usage: &usage)
        for term in try polynomial.orderedTerms(usage: &usage) {
            var value = try OriginalSingularFieldElement.constant(term.value, in: context,
                maximumDepth: maximumDepth, usage: &usage)
            for coordinate in coordinates.indices {
                try intersectionAlgebraStep(&usage)
                let exponent = try term.key.exponent(at: coordinate)
                if exponent == 0 { continue }
                value = try value.multiplied(by: power(coordinates[coordinate],
                    exponent: exponent, maximumDepth: maximumDepth, usage: &usage),
                    maximumDepth: maximumDepth, usage: &usage)
            }
            result = try result.adding(value, maximumDepth: maximumDepth, usage: &usage)
        }
        return result
    }

    package static func power<B: RationalAlgebraAdmitting>(_ value: OriginalSingularFieldElement,
        exponent: Int, maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldElement {
        guard exponent >= 0 else { throw rationalAlgebraFailure("Original field powers require nonnegative exponents.") }
        try intersectionAlgebraStep(&usage)
        if exponent == 1 { return value }
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

    private static func rationalCoordinates<B: RationalAlgebraAdmitting>(context: OriginalSingularFieldContext,
        coordinates: [OriginalSingularFieldElement], usage: inout B) throws -> [ExactRationalCoefficient] {
        try RationalAlgebraStorage.retain(coordinates.count, of: ExactRationalCoefficient.self, usage: &usage)
        var values: [ExactRationalCoefficient] = []; values.reserveCapacity(coordinates.count)
        for coordinate in coordinates {
            try intersectionAlgebraStep(&usage)
            guard coordinate.context === context, let value = try coordinate.rationalValue(usage: &usage) else {
                throw rationalAlgebraFailure("Rational prefix substitution requires its original rational owner and values.")
            }
            values.append(value)
        }
        return values
    }

    private static func rationalPower<B: RationalAlgebraAdmitting>(_ value: ExactRationalCoefficient,
        exponent: Int, usage: inout B) throws -> ExactRationalCoefficient {
        try intersectionAlgebraStep(&usage)
        guard exponent >= 0 else { throw rationalAlgebraFailure("Original rational powers require nonnegative exponents.") }
        if exponent == 1 { return value }
        var result = ExactRationalCoefficient.one, factor = value, exponent = exponent
        while exponent > 0 {
            try intersectionAlgebraStep(&usage)
            if exponent & 1 != 0 { result = try result.multiplied(by: factor, usage: &usage) }
            exponent /= 2
            if exponent > 0 { factor = try factor.multiplied(by: factor, usage: &usage) }
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
