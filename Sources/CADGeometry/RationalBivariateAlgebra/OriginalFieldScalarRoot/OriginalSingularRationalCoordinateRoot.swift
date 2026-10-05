import CADCore

/// A rational scalar endpoint retaining the ORIGINAL real field value that issued it.
package struct OriginalSingularRationalCoordinateRoot: Sendable {
    package let original: OriginalSingularFieldElement
    package let endpoint: ExactMonotoneGraphEndpoint
    package let annihilator: ExactBivariatePolynomial
    package let sourceIsolation: OriginalSingularFieldValueIsolation

    package init<B: RationalAlgebraAdmitting>(original: OriginalSingularFieldElement,
        maximumDepth: Int, maximumAlgebraicDepth: Int, usage: inout B) throws {
        guard maximumDepth >= original.context.depth, (0...32).contains(maximumAlgebraicDepth),
            original.context.coefficientDepth <= maximumAlgebraicDepth else {
            throw rationalAlgebraFailure("Original scalar transport exceeds the caller's independent depth domains.")
        }
        var admission = Admission(original: usage, maximumDepth: maximumDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, reachedDepth: original.context.depth)
        defer { usage = admission.original }
        self.original = original
        try RationalAlgebraStorage.retain(2, of: OriginalSingularFieldElement.self, usage: &admission)
        let minus = try OriginalSingularFieldElement.constant(.one.negated, in: original.context,
            maximumDepth: maximumDepth, usage: &admission)
        let negative = try original.multiplied(by: minus, maximumDepth: maximumDepth, usage: &admission)
        let one = try OriginalSingularFieldElement.constant(.one, in: original.context,
            maximumDepth: maximumDepth, usage: &admission)
        let equation = try OriginalSingularFieldPolynomial(context: original.context,
            coefficients: [negative, one], maximumDepth: maximumDepth, usage: &admission)
        let rational = try OriginalFieldPolynomialNorm.rationalNorm(equation,
            maximumDepth: maximumDepth, usage: &admission)
        let sequence = try ExactUnivariateSturmSequence(rational, usage: &admission)
        guard sequence.source.uDegree > 0 else { throw rationalAlgebraFailure("Original scalar norm has no nonconstant rational source law.") }
        annihilator = sequence.source
        // A retained source value must satisfy the result; no conjugate is selected from a numerical point.
        var value = try OriginalSingularFieldElement.constant(.zero, in: original.context,
            maximumDepth: maximumDepth, usage: &admission)
        for degree in (0...sequence.source.uDegree).reversed() {
            let coefficient = sequence.source.originalCoefficients[try .init(u: degree, v: 0)] ?? .zero
            value = try value.multiplied(by: original, maximumDepth: maximumDepth, usage: &admission)
                .adding(.constant(coefficient, in: original.context, maximumDepth: maximumDepth, usage: &admission),
                    maximumDepth: maximumDepth, usage: &admission)
        }
        guard case .zero = try value.sign(maximumDepth: maximumDepth, usage: &admission) else {
            throw rationalAlgebraFailure("Original rational norm does not annihilate its retained source value.")
        }
        var isolation = try OriginalSingularFieldValueIsolation(original: original,
            inheritedDepth: admission.reachedDepth, maximumDepth: maximumDepth, usage: &admission)
        var width = ExactRationalCoefficient.one
        while true {
            let firstComparison = try isolation.compared(to: isolation.lower,
                maximumDepth: maximumDepth, usage: &admission)
            isolation = firstComparison.isolation
            let lastComparison = try isolation.compared(to: isolation.upper,
                maximumDepth: maximumDepth, usage: &admission)
            isolation = lastComparison.isolation
            let first = firstComparison.sign, last = lastComparison.sign
            let excludesLower: Bool, excludesUpper: Bool
            if case .zero = first { excludesLower = false } else { excludesLower = true }
            if case .zero = last { excludesUpper = false } else { excludesUpper = true }
            let count = try sequence.count(lower: isolation.lower, upper: isolation.upper,
                excludesLower: excludesLower, excludesUpper: excludesUpper, usage: &admission)
            guard count > 0 else { throw rationalAlgebraFailure("Original scalar value has no norm root inside its retained exact bounds.") }
            if count == 1 {
                let bounds = ExactUnivariateRootIsolator.Root(lower: isolation.lower, upper: isolation.upper,
                    isRationalStation: isolation.lower == isolation.upper, isolationDepth: isolation.sourceDepth,
                    excludesLowerEndpoint: excludesLower, excludesUpperEndpoint: excludesUpper)
                endpoint = try .algebraic(ExactAlgebraicRealRoot(polynomial: sequence.source,
                    isolation: bounds, usage: &admission))
                sourceIsolation = isolation
                try RationalAlgebraStorage.retain(1, of: Self.self, usage: &admission)
                return
            }
            isolation = try isolation.refined(maximumWidth: width, maximumDepth: maximumDepth, usage: &admission)
            width = try width.divided(by: .natural(2, usage: &admission), usage: &admission)
        }
    }

    private struct Admission<B: RationalAlgebraAdmitting>: RationalAlgebraAdmitting {
        var original: B
        let maximumDepth: Int
        let maximumAlgebraicDepth: Int
        var reachedDepth: Int
        mutating func consumeExactWork(_ count: Int) throws { try original.consumeExactWork(count) }
        mutating func retainExactStorage(_ count: Int) throws { try original.retainExactStorage(count) }
        mutating func visitExactCell(depth: Int) throws {
            guard depth >= 0, depth <= maximumDepth else { throw rationalAlgebraFailure("Original scalar transport exhausted geometric root depth.") }
            reachedDepth = max(reachedDepth, depth)
            try original.visitExactCell(depth: depth)
        }
        mutating func visitCoefficientCell(depth: Int) throws {
            guard depth >= 0, depth <= maximumAlgebraicDepth else { throw rationalAlgebraFailure("Original scalar transport exhausted coefficient root depth.") }
            try original.visitCoefficientCell(depth: depth)
        }
    }
}
