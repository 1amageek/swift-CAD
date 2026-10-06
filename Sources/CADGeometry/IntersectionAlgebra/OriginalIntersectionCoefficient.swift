import CADCore

/// One original ordered coefficient and its proved selected rational-law embedding.
package struct OriginalIntersectionCoefficient: Sendable {
    package enum Representation: Sendable {
        case rational(ExactRationalCoefficient)
        case algebraic(annihilator: ExactBivariatePolynomial, root: OriginalSingularFieldRoot)
    }
    package let original: OriginalSingularFieldElement
    package let representation: Representation
    package let parameterAdmissionDepth: Int
    package let coefficientAdmissionDepth: Int

    private init(original: OriginalSingularFieldElement, representation: Representation,
        parameterAdmissionDepth: Int, coefficientAdmissionDepth: Int) {
        self.original = original; self.representation = representation
        self.parameterAdmissionDepth = parameterAdmissionDepth
        self.coefficientAdmissionDepth = coefficientAdmissionDepth
    }

    package static func prepare<B: RationalAlgebraAdmitting>(original: OriginalSingularFieldElement,
        maximumDepth: Int, maximumCoefficientDepth: Int, usage: inout B) throws -> Self {
        guard maximumDepth >= 0, (0...32).contains(maximumCoefficientDepth),
            original.context.depth <= maximumDepth,
            original.context.coefficientDepth <= maximumCoefficientDepth else {
            throw rationalAlgebraFailure("Original coefficient transport exceeds its independent retained depth domains.")
        }
        var admission = Admission(base: usage, maximumDepth: maximumDepth,
            maximumCoefficientDepth: maximumCoefficientDepth,
            parameterDepth: original.context.depth, coefficientDepth: original.context.coefficientDepth)
        defer { usage = admission.base }
        try intersectionAlgebraStep(&admission)
        if let rational = try original.rationalValue(usage: &admission) {
            try RationalAlgebraStorage.retain(1, of: Self.self, usage: &admission)
            return Self(original: original, representation: .rational(rational),
                parameterAdmissionDepth: admission.parameterDepth, coefficientAdmissionDepth: admission.coefficientDepth)
        }
        let negative = try original.negated(maximumDepth: maximumDepth, usage: &admission)
        let one = try OriginalSingularFieldElement.constant(.one, in: original.context,
            maximumDepth: maximumDepth, usage: &admission)
        try RationalAlgebraStorage.retain(2, of: OriginalSingularFieldElement.self, usage: &admission)
        let equation = try OriginalSingularFieldPolynomial(context: original.context,
            coefficients: [negative, one], maximumDepth: maximumDepth, usage: &admission)
        let annihilator = try OriginalFieldPolynomialNorm.rationalNorm(equation,
            maximumDepth: maximumDepth, usage: &admission)
        guard !annihilator.isZero, annihilator.uDegree > 0, annihilator.vDegree <= 0 else {
            throw rationalAlgebraFailure("Original coefficient norm lost its nonconstant rational scalar law.")
        }
        var checked = try OriginalSingularFieldElement.constant(.zero, in: original.context,
            maximumDepth: maximumDepth, usage: &admission)
        for degree in (0...annihilator.uDegree).reversed() {
            try intersectionAlgebraStep(&admission)
            let coefficient = annihilator.originalCoefficients[try .init(u: degree, v: 0)] ?? .zero
            checked = try checked.multiplied(by: original, maximumDepth: maximumDepth, usage: &admission)
                .adding(.constant(coefficient, in: original.context,
                    maximumDepth: maximumDepth, usage: &admission), maximumDepth: maximumDepth, usage: &admission)
        }
        guard try checked.sign(maximumDepth: maximumDepth, usage: &admission) == .zero else {
            throw rationalAlgebraFailure("Original coefficient does not satisfy its retained rational annihilator.")
        }
        let rational = try OriginalSingularFieldContext(usage: &admission)
        let count = try rationalAlgebraCount(annihilator.uDegree, 1)
        try RationalAlgebraStorage.retain(count, of: OriginalSingularFieldElement.self, usage: &admission)
        var coefficients: [OriginalSingularFieldElement] = []; coefficients.reserveCapacity(count)
        for degree in 0..<count {
            let coefficient = annihilator.originalCoefficients[try .init(u: degree, v: 0)] ?? .zero
            coefficients.append(try .constant(coefficient, in: rational, maximumDepth: maximumDepth, usage: &admission))
        }
        let law = try OriginalSingularFieldPolynomial(context: rational, coefficients: coefficients,
            maximumDepth: maximumDepth, usage: &admission)
        let roots = try OriginalSingularFieldRoot.allRealRoots(law, inheritedDepth: admission.coefficientDepth,
            maximumDepth: maximumDepth, admissionDomain: .coefficient(maximumDepth: maximumCoefficientDepth),
            usage: &admission)
        var selected: OriginalSingularFieldRoot?
        for root in roots {
            try intersectionAlgebraStep(&admission)
            let lower = try OriginalSingularFieldElement.constant(root.isolation.lower, in: original.context,
                maximumDepth: maximumDepth, usage: &admission)
            let upper = try OriginalSingularFieldElement.constant(root.isolation.upper, in: original.context,
                maximumDepth: maximumDepth, usage: &admission)
            let a = try original.subtracting(lower, maximumDepth: maximumDepth, usage: &admission)
                .sign(maximumDepth: maximumDepth, usage: &admission)
            let b = try original.subtracting(upper, maximumDepth: maximumDepth, usage: &admission)
                .sign(maximumDepth: maximumDepth, usage: &admission)
            if a == .negative || a == .zero && root.isolation.excludesLower { continue }
            if b == .positive || b == .zero && root.isolation.excludesUpper { continue }
            guard selected == nil else {
                throw rationalAlgebraFailure("Original coefficient belongs to more than one issued real isolation.")
            }
            selected = root
        }
        guard let root = selected else {
            throw rationalAlgebraFailure("Original coefficient has no selected root in the complete real norm coverage.")
        }
        let depth = max(admission.coefficientDepth, root.isolation.depth)
        let retained = OriginalSingularFieldRoot(polynomial: root.polynomial,
            isolation: .init(lower: root.isolation.lower, upper: root.isolation.upper,
                excludesLower: root.isolation.excludesLower, excludesUpper: root.isolation.excludesUpper, depth: depth),
            admissionDomain: root.admissionDomain)
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &admission)
        return Self(original: original, representation: .algebraic(annihilator: annihilator, root: retained),
            parameterAdmissionDepth: admission.parameterDepth, coefficientAdmissionDepth: depth)
    }

    private struct Admission<B: RationalAlgebraAdmitting>: RationalAlgebraAdmitting {
        var base: B
        let maximumDepth: Int
        let maximumCoefficientDepth: Int
        var parameterDepth: Int
        var coefficientDepth: Int
        mutating func consumeExactWork(_ count: Int) throws {
            try Task.checkCancellation(); try base.consumeExactWork(count)
        }
        mutating func retainExactStorage(_ count: Int) throws {
            try Task.checkCancellation(); try base.retainExactStorage(count)
        }
        mutating func visitExactCell(depth: Int) throws {
            try Task.checkCancellation()
            guard depth >= 0, depth <= maximumDepth else {
                throw rationalAlgebraFailure("Original coefficient source exhausted parameter root depth.")
            }
            parameterDepth = max(parameterDepth, depth); try base.visitExactCell(depth: depth)
        }
        mutating func visitCoefficientCell(depth: Int) throws {
            try Task.checkCancellation()
            guard depth >= 0, depth <= maximumCoefficientDepth else {
                throw rationalAlgebraFailure("Original coefficient transport exhausted coefficient root depth.")
            }
            coefficientDepth = max(coefficientDepth, depth); try base.visitCoefficientCell(depth: depth)
        }
    }
}
