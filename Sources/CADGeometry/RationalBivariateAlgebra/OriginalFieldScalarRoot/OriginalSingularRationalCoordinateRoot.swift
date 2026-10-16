import CADCore

/// A rational scalar endpoint retaining the ORIGINAL real field value that issued it.
package struct OriginalSingularRationalCoordinateRoot: Sendable {
    package let original: OriginalSingularFieldElement
    package let endpoint: ExactMonotoneGraphEndpoint
    package let annihilator: ExactBivariatePolynomial
    package let sourceIsolation: OriginalSingularFieldValueIsolation

    package init<B: ExactScalarAdmission & ~Copyable>(original: OriginalSingularFieldElement,
        maximumDepth: Int, maximumAlgebraicDepth: Int, usage: inout B) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard maximumDepth >= original.context.depth, (0...32).contains(maximumAlgebraicDepth),
            original.context.coefficientDepth <= maximumAlgebraicDepth else {
            throw rationalAlgebraFailure("Original scalar transport exceeds the caller's independent depth domains.")
        }
        self = try usage.withProofScope(maximum: .init(value: maximumDepth,
            coefficient: maximumAlgebraicDepth)) { usage in
            var isolation = try OriginalSingularFieldValueIsolation(original: original,
                inheritedDepth: original.context.depth, maximumDepth: maximumDepth, usage: &usage)
            return try Self(isolation: &isolation, maximumDepth: maximumDepth,
                maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &usage)
        }
    }

    /// Binds the retained source enclosure without restarting its causal depth.
    package init<B: ExactScalarAdmission & ~Copyable>(isolation: inout OriginalSingularFieldValueIsolation,
        maximumDepth: Int, maximumAlgebraicDepth: Int, usage: inout B) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        let original = isolation.original
        guard maximumDepth >= isolation.sourceDepth, isolation.sourceDepth >= original.context.depth,
            (0...32).contains(maximumAlgebraicDepth),
            original.context.coefficientDepth <= maximumAlgebraicDepth else {
            throw rationalAlgebraFailure("Original scalar transport exceeds the caller's independent depth domains.")
        }
        let available = try rationalAlgebraCount(original.context.depth, maximumDepth - isolation.sourceDepth)
        let preparation = try usage.withProofScope(
            original: .init(value: original.context.depth, coefficient: 0),
            inherited: .init(value: isolation.sourceDepth, coefficient: 0),
            maximum: .init(value: maximumDepth, coefficient: maximumAlgebraicDepth)
        ) { usage in
            try RationalAlgebraStorage.retain(2, of: OriginalSingularFieldElement.self, usage: &usage)
            let minus = try OriginalSingularFieldElement.constant(.one.negated, in: original.context,
                maximumDepth: available, usage: &usage)
            let negative = try original.multiplied(by: minus, maximumDepth: available, usage: &usage)
            let one = try OriginalSingularFieldElement.constant(.one, in: original.context,
                maximumDepth: available, usage: &usage)
            let equation = try OriginalSingularFieldPolynomial(context: original.context,
                coefficients: [negative, one], maximumDepth: available, usage: &usage)
            let rational = try OriginalFieldPolynomialNorm.rationalNorm(equation,
                maximumDepth: available, usage: &usage)
            let sequence = try ExactUnivariateSturmSequence(rational, usage: &usage)
            guard sequence.source.uDegree > 0 else { throw rationalAlgebraFailure("Original scalar norm has no nonconstant rational source law.") }
            // A retained source value must satisfy the result; no conjugate is selected from a numerical point.
            var value = try OriginalSingularFieldElement.constant(.zero, in: original.context,
                maximumDepth: available, usage: &usage)
            for degree in (0...sequence.source.uDegree).reversed() {
                let coefficient = sequence.source.originalCoefficients[try .init(u: degree, v: 0)] ?? .zero
                value = try value.multiplied(by: original, maximumDepth: available, usage: &usage)
                    .adding(.constant(coefficient, in: original.context, maximumDepth: available, usage: &usage),
                        maximumDepth: available, usage: &usage)
            }
            guard case .zero = try value.sign(maximumDepth: available, usage: &usage) else {
                throw rationalAlgebraFailure("Original rational norm does not annihilate its retained source value.")
            }
            return (sequence: sequence, reached: try usage.depth.value)
        }
        let sequence = preparation.sequence
        let result = try usage.withProofScope(maximum: .init(value: maximumDepth,
            coefficient: maximumAlgebraicDepth)) { usage in
            // The persistent isolation owns subsequent depth mapping.
            isolation = try isolation.inheriting(depth: preparation.reached,
                maximumDepth: maximumDepth, usage: &usage)
            var width = ExactRationalCoefficient.one
            while true {
                let firstComparison = try isolation.compared(to: isolation.lower,
                    maximumDepth: maximumDepth, usage: &usage)
                isolation = firstComparison.isolation
                let lastComparison = try isolation.compared(to: isolation.upper,
                    maximumDepth: maximumDepth, usage: &usage)
                isolation = lastComparison.isolation
                let first = firstComparison.sign, last = lastComparison.sign
                let excludesLower: Bool, excludesUpper: Bool
                if case .zero = first { excludesLower = false } else { excludesLower = true }
                if case .zero = last { excludesUpper = false } else { excludesUpper = true }
                let count = try sequence.count(lower: isolation.lower, upper: isolation.upper,
                    excludesLower: excludesLower, excludesUpper: excludesUpper, usage: &usage)
                guard count > 0 else { throw rationalAlgebraFailure("Original scalar value has no norm root inside its retained exact bounds.") }
                if count == 1 {
                    let bounds = ExactUnivariateRootIsolator.Root(lower: isolation.lower, upper: isolation.upper,
                        isRationalStation: isolation.lower == isolation.upper, isolationDepth: isolation.sourceDepth,
                        excludesLowerEndpoint: excludesLower, excludesUpperEndpoint: excludesUpper)
                    let endpoint = try ExactMonotoneGraphEndpoint.algebraic(ExactAlgebraicRealRoot(polynomial: sequence.source,
                        isolation: bounds, usage: &usage))
                    try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
                    try CurrentTaskCancellationChecker().checkCancellation()
                    return (endpoint: endpoint, isolation: isolation)
                }
                isolation = try isolation.refined(maximumWidth: width, maximumDepth: maximumDepth, usage: &usage)
                width = try width.divided(by: .natural(2, usage: &usage), usage: &usage)
            }
        }
        self.original = original
        annihilator = sequence.source
        endpoint = result.endpoint
        sourceIsolation = result.isolation
    }
}
