/// A source-bound affine image of one retained original section root.
struct NativeCurveSurfaceScalarLocalization: Sendable {
    let original: OriginalSingularFieldElement
    let primitiveCoordinate: OriginalSingularFieldElement
    let primitive: OriginalSingularFieldRoot
    let multiplier: ExactRationalCoefficient
    let offset: ExactRationalCoefficient
    let identityDifference: OriginalSingularFieldElement
    let parameterDepth: Int
    let coefficientDepth: Int

    static func prepare<B: RationalAlgebraAdmitting>(original: OriginalSingularFieldElement,
        sectionCoordinate: OriginalSingularFieldElement, isolation: OriginalSingularFieldValueIsolation,
        inheritedCoefficientDepth: Int, maximumDepth: Int, maximumCoefficientDepth: Int,
        usage: inout B) throws -> Self? {
        guard case .extended(let root) = sectionCoordinate.context.source,
            case .parameter = root.admissionDomain else { return nil }
        var admission = OriginalSourceScalarAdmission(base: usage, maximumDepth: maximumDepth,
            maximumCoefficientDepth: maximumCoefficientDepth,
            originalParameterDepth: original.context.depth,
            originalCoefficientDepth: original.context.coefficientDepth,
            inheritedParameterDepth: isolation.sourceDepth,
            inheritedCoefficientDepth: inheritedCoefficientDepth,
            parameterDepth: isolation.sourceDepth, coefficientDepth: inheritedCoefficientDepth)
        defer { usage = admission.base }
        let available = try rationalAlgebraCount(original.context.depth, maximumDepth - isolation.sourceDepth)
        for coefficient in root.polynomial.coefficients {
            try admission.consumeExactWork(1)
            guard try coefficient.rationalValue(usage: &admission) != nil else { return nil }
        }
        var value = original
        while value.context !== sectionCoordinate.context {
            try admission.consumeExactWork(1)
            guard case .extended(let fiber) = value.context.source,
                case .extended(let numerator, let denominator) = value.storage else { return nil }
            if numerator.degree <= 0, denominator.degree == 0 {
                let a: OriginalSingularFieldElement
                if let coefficient = numerator.coefficients.first { a = coefficient }
                else { a = try .constant(.zero, in: numerator.context, maximumDepth: available, usage: &admission) }
                value = try a.divided(by: denominator.coefficients[0], maximumDepth: available, usage: &admission)
            } else if fiber.polynomial.degree == 1 {
                // The original linear fiber has exactly this parent-field value.
                let station = try fiber.polynomial.coefficients[0].negated(maximumDepth: available, usage: &admission)
                    .divided(by: fiber.polynomial.coefficients[1], maximumDepth: available, usage: &admission)
                value = try numerator.evaluated(at: station, maximumDepth: available, usage: &admission)
                    .divided(by: denominator.evaluated(at: station, maximumDepth: available, usage: &admission),
                        maximumDepth: available, usage: &admission)
            } else { return nil }
        }
        guard case .extended(let numerator, let denominator) = value.storage,
            numerator.degree <= 1, denominator.degree == 0,
            let divisor = try denominator.coefficients[0].rationalValue(usage: &admission), !divisor.isZero else { return nil }
        let constant: ExactRationalCoefficient
        if let coefficient = numerator.coefficients.first {
            guard let rational = try coefficient.rationalValue(usage: &admission) else { return nil }
            constant = rational
        } else { constant = .zero }
        let slope: ExactRationalCoefficient
        if numerator.degree == 1 {
            guard let rational = try numerator.coefficients[1].rationalValue(usage: &admission) else { return nil }
            slope = rational
        } else { slope = .zero }
        let multiplier = try slope.divided(by: divisor, usage: &admission)
        let offset = try constant.divided(by: divisor, usage: &admission)
        let a = try OriginalSingularFieldElement.constant(multiplier, in: sectionCoordinate.context,
            maximumDepth: available, usage: &admission)
        let b = try OriginalSingularFieldElement.constant(offset, in: sectionCoordinate.context,
            maximumDepth: available, usage: &admission)
        let image = try sectionCoordinate.multiplied(by: a, maximumDepth: available, usage: &admission)
            .adding(b, maximumDepth: available, usage: &admission).embedded(in: original.context,
                maximumDepth: available, usage: &admission)
        let difference = try original.subtracting(image, maximumDepth: available, usage: &admission)
        guard try difference.sign(maximumDepth: available, usage: &admission) == .zero else {
            throw rationalAlgebraFailure("Native affine localization contradicts its original final field coordinate.")
        }
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &admission)
        return Self(original: original, primitiveCoordinate: sectionCoordinate, primitive: root,
            multiplier: multiplier, offset: offset, identityDifference: difference,
            parameterDepth: admission.parameterDepth, coefficientDepth: admission.coefficientDepth)
    }

    func refined<B: RationalAlgebraAdmitting>(maximumWidth: ExactRationalCoefficient,
        isolation: OriginalSingularFieldValueIsolation, reusing other: Self?, maximumDepth: Int,
        maximumCoefficientDepth: Int, usage: inout B) throws -> (proof: Self, isolation: OriginalSingularFieldValueIsolation) {
        guard isolation.original.context === original.context,
            isolation.sourceDepth >= parameterDepth, maximumWidth.isPositive else {
            throw rationalAlgebraFailure("Native affine refinement requires its retained source and causal bounds.")
        }
        var root = primitive
        var inherited = max(parameterDepth, isolation.sourceDepth)
        var inheritedCoefficient = coefficientDepth
        if let other, other.primitiveCoordinate.context === primitiveCoordinate.context {
            // Identical immutable root owner grants reuse of its achieved proof.
            root = other.primitive
            inherited = max(inherited, other.parameterDepth)
            inheritedCoefficient = max(inheritedCoefficient, other.coefficientDepth)
        }
        var admission = OriginalSourceScalarAdmission(base: usage, maximumDepth: maximumDepth,
            maximumCoefficientDepth: maximumCoefficientDepth,
            originalParameterDepth: root.isolation.depth,
            originalCoefficientDepth: root.polynomial.context.coefficientDepth,
            inheritedParameterDepth: inherited, inheritedCoefficientDepth: inheritedCoefficient,
            parameterDepth: inherited, coefficientDepth: inheritedCoefficient)
        defer { usage = admission.base }
        let available = try rationalAlgebraCount(root.isolation.depth, maximumDepth - inherited)
        if !multiplier.isZero {
            let magnitude = multiplier.isNegative ? multiplier.negated : multiplier
            let width = try maximumWidth.divided(by: magnitude, usage: &admission)
            root = try root.refined(maximumWidth: width, maximumDepth: available, usage: &admission)
        }
        let a = try root.isolation.lower.multiplied(by: multiplier, usage: &admission).adding(offset, usage: &admission)
        let b = try root.isolation.upper.multiplied(by: multiplier, usage: &admission).adding(offset, usage: &admission)
        let lower = multiplier.isNegative ? b : a, upper = multiplier.isNegative ? a : b
        let bounds = root.isolation
        let retainedRoot = OriginalSingularFieldRoot(polynomial: root.polynomial,
            isolation: .init(lower: bounds.lower, upper: bounds.upper, excludesLower: bounds.excludesLower,
                excludesUpper: bounds.excludesUpper, depth: admission.parameterDepth), admissionDomain: root.admissionDomain)
        // The prefix root's exact affine image must enclose the original final
        // field value. Its owner and original source are never replaced.
        var validation = OriginalSourceScalarAdmission(base: admission.base, maximumDepth: maximumDepth,
            maximumCoefficientDepth: maximumCoefficientDepth, originalParameterDepth: 0,
            originalCoefficientDepth: original.context.coefficientDepth,
            inheritedParameterDepth: 0, inheritedCoefficientDepth: admission.coefficientDepth,
            parameterDepth: admission.parameterDepth, coefficientDepth: admission.coefficientDepth)
        defer { admission.base = validation.base }
        let retained = try OriginalSingularFieldValueIsolation(original: original, lower: lower, upper: upper,
            inheritedDepth: admission.parameterDepth, maximumDepth: maximumDepth, usage: &validation)
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &validation)
        return (Self(original: original, primitiveCoordinate: primitiveCoordinate, primitive: retainedRoot,
            multiplier: multiplier, offset: offset, identityDifference: identityDifference,
            parameterDepth: retained.sourceDepth, coefficientDepth: validation.coefficientDepth), retained)
    }
}
