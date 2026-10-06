import CADCore

/// A rational scalar endpoint retaining the ORIGINAL real field value that issued it.
package struct OriginalSingularRationalCoordinateRoot: Sendable {
    package let original: OriginalSingularFieldElement
    package let endpoint: ExactMonotoneGraphEndpoint
    package let annihilator: ExactBivariatePolynomial
    package let sourceIsolation: OriginalSingularFieldValueIsolation

    package init<B: RationalAlgebraAdmitting>(original: OriginalSingularFieldElement,
        maximumDepth: Int, maximumAlgebraicDepth: Int, usage: inout B) throws {
        try Task.checkCancellation()
        guard maximumDepth >= original.context.depth, (0...32).contains(maximumAlgebraicDepth),
            original.context.coefficientDepth <= maximumAlgebraicDepth else {
            throw rationalAlgebraFailure("Original scalar transport exceeds the caller's independent depth domains.")
        }
        // Fresh ValueIsolation already maps its own source depth; this wrapper
        // only guards both caller domains while forwarding the same paid ledger.
        var admission = Admission(original: usage, maximumDepth: maximumDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, originalDepth: original.context.depth,
            inheritedDepth: original.context.depth, reachedDepth: original.context.depth,
            mapsOriginalDepth: false)
        defer { usage = admission.original }
        var isolation = try OriginalSingularFieldValueIsolation(original: original,
            inheritedDepth: original.context.depth, maximumDepth: maximumDepth, usage: &admission)
        try self.init(isolation: &isolation, maximumDepth: maximumDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &admission)
    }

    /// Binds the retained source enclosure without restarting its causal depth.
    package init<B: RationalAlgebraAdmitting>(isolation: inout OriginalSingularFieldValueIsolation,
        maximumDepth: Int, maximumAlgebraicDepth: Int, usage: inout B) throws {
        try Task.checkCancellation()
        let original = isolation.original
        guard maximumDepth >= isolation.sourceDepth, isolation.sourceDepth >= original.context.depth,
            (0...32).contains(maximumAlgebraicDepth),
            original.context.coefficientDepth <= maximumAlgebraicDepth else {
            throw rationalAlgebraFailure("Original scalar transport exceeds the caller's independent depth domains.")
        }
        let available = try rationalAlgebraCount(original.context.depth, maximumDepth - isolation.sourceDepth)
        var admission = Admission(original: usage, maximumDepth: maximumDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, originalDepth: original.context.depth,
            inheritedDepth: isolation.sourceDepth, reachedDepth: isolation.sourceDepth)
        defer { usage = admission.original }
        self.original = original
        try RationalAlgebraStorage.retain(2, of: OriginalSingularFieldElement.self, usage: &admission)
        let minus = try OriginalSingularFieldElement.constant(.one.negated, in: original.context,
            maximumDepth: available, usage: &admission)
        let negative = try original.multiplied(by: minus, maximumDepth: available, usage: &admission)
        let one = try OriginalSingularFieldElement.constant(.one, in: original.context,
            maximumDepth: available, usage: &admission)
        let equation = try OriginalSingularFieldPolynomial(context: original.context,
            coefficients: [negative, one], maximumDepth: available, usage: &admission)
        let rational = try OriginalFieldPolynomialNorm.rationalNorm(equation,
            maximumDepth: available, usage: &admission)
        let sequence = try ExactUnivariateSturmSequence(rational, usage: &admission)
        guard sequence.source.uDegree > 0 else { throw rationalAlgebraFailure("Original scalar norm has no nonconstant rational source law.") }
        annihilator = sequence.source
        // A retained source value must satisfy the result; no conjugate is selected from a numerical point.
        var value = try OriginalSingularFieldElement.constant(.zero, in: original.context,
            maximumDepth: available, usage: &admission)
        for degree in (0...sequence.source.uDegree).reversed() {
            let coefficient = sequence.source.originalCoefficients[try .init(u: degree, v: 0)] ?? .zero
            value = try value.multiplied(by: original, maximumDepth: available, usage: &admission)
                .adding(.constant(coefficient, in: original.context, maximumDepth: available, usage: &admission),
                    maximumDepth: available, usage: &admission)
        }
        guard case .zero = try value.sign(maximumDepth: available, usage: &admission) else {
            throw rationalAlgebraFailure("Original rational norm does not annihilate its retained source value.")
        }
        // ValueIsolation maps its own persistent depth; do not map it twice.
        admission.mapsOriginalDepth = false
        isolation = try isolation.inheriting(depth: admission.reachedDepth,
            maximumDepth: maximumDepth, usage: &admission)
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
                try Task.checkCancellation()
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
        let originalDepth: Int
        let inheritedDepth: Int
        var reachedDepth: Int
        var mapsOriginalDepth = true
        mutating func consumeExactWork(_ count: Int) throws { try Task.checkCancellation(); try original.consumeExactWork(count) }
        mutating func retainExactStorage(_ count: Int) throws { try Task.checkCancellation(); try original.retainExactStorage(count) }
        mutating func visitExactCell(depth: Int) throws {
            try Task.checkCancellation()
            let mapped = mapsOriginalDepth
                ? try rationalAlgebraCount(inheritedDepth, max(0, depth - originalDepth)) : depth
            guard depth >= 0, mapped <= maximumDepth else { throw rationalAlgebraFailure("Original scalar transport exhausted geometric root depth.") }
            reachedDepth = max(reachedDepth, mapped)
            try original.visitExactCell(depth: mapped)
        }
        mutating func visitCoefficientCell(depth: Int) throws {
            try Task.checkCancellation()
            guard depth >= 0, depth <= maximumAlgebraicDepth else { throw rationalAlgebraFailure("Original scalar transport exhausted coefficient root depth.") }
            try original.visitCoefficientCell(depth: depth)
        }
    }
}
