import CADCore

/// Original inverse blowup word composed with one retained rational pcurve span.
struct OriginalRamifiedSilhouetteBoundaryMap: Sendable {
    let localU: OriginalFieldUnivariateRationalFunction
    let localV: OriginalFieldUnivariateRationalFunction
    let strictTransform: OriginalFieldUnivariateRationalFunction
    let centerU: OriginalSingularFieldElement
    let centerV: OriginalSingularFieldElement
    let chart: OriginalSingularRegularChart
    let exceptionalOnly: Bool

    init(image: SurfaceSilhouetteRamifiedParameterImage,
        u: OriginalSingularFieldPolynomial, v: OriginalSingularFieldPolynomial,
        weight: OriginalSingularFieldPolynomial, usage: inout OriginalQueryExecution) throws {
        chart = image.original
        let context = u.context
        let zero = try OriginalSingularFieldElement.constant(.zero, in: context,
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        let sourceU = try OriginalFieldUnivariateRationalFunction(numerator: u, denominator: weight,
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        let sourceV = try OriginalFieldUnivariateRationalFunction(numerator: v, denominator: weight,
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        centerU = try chart.germ.originalU.evaluated(atU: zero, v: zero,
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        centerV = try chart.germ.originalV.evaluated(atU: zero, v: zero,
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        var x = try sourceU.subtracting(.constant(centerU, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage),
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        var y = try sourceV.subtracting(.constant(centerV, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage),
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        var exceptional = false
        inverseSteps: for step in chart.germ.steps {
            try usage.visitSilhouetteCell(depth: max(step.sourceDepth, image.refinementDepth))
            switch step.direction {
            case .finite:
                guard let tangent = step.tangentValue else {
                    throw rationalAlgebraFailure("Original ramified boundary map lost its exact tangent owner.")
                }
                let slope = try tangent.embedded(in: context, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
                if x.numerator.isZero {
                    if y.numerator.isZero { continue }
                    // An entire exceptional direction can only meet this local
                    // chart at the original center. Retain that exact event law.
                    exceptional = true; break inverseSteps
                }
                y = try y.divided(by: x, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
                    .subtracting(.constant(slope, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage),
                        maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            case .vertical:
                if y.numerator.isZero {
                    if x.numerator.isZero { continue }
                    exceptional = true; break inverseSteps
                }
                let first = y
                y = try x.divided(by: y, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage); x = first
            }
        }
        exceptionalOnly = exceptional
        localU = x; localV = y
        strictTransform = try .composed(chart.germ.strictTransform.embedded(in: context,
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage), withU: x, v: y,
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
    }

    func originalParameter(at t: OriginalSingularFieldElement,
        originalU: OriginalSingularFieldElement, originalV: OriginalSingularFieldElement,
        usage: inout OriginalQueryExecution) throws -> OriginalSingularFieldElement? {
        let centerU = try self.centerU.embedded(in: t.context, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        let centerV = try self.centerV.embedded(in: t.context, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        let x: OriginalSingularFieldElement, y: OriginalSingularFieldElement
        if case .zero = try originalU.subtracting(centerU, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            .sign(maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage),
            case .zero = try originalV.subtracting(centerV, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            .sign(maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) {
            x = try .constant(.zero, in: t.context, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage); y = x
        } else {
            if exceptionalOnly { return nil }
            if case .zero = try localU.denominator.evaluated(at: t, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
                .sign(maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) { return nil }
            if case .zero = try localV.denominator.evaluated(at: t, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
                .sign(maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) { return nil }
            x = try localU.evaluated(at: t, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            y = try localV.evaluated(at: t, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        }
        guard case .zero = try chart.germ.strictTransform.evaluated(atU: x, v: y,
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage).sign(maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) else { return nil }
        for (coordinate, bounds) in [(x, chart.localDomain.u), (y, chart.localDomain.v)] {
            let lower = try OriginalSingularFieldElement.constant(.originalDouble(bounds.lower, usage: &usage),
                in: t.context, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            let upper = try OriginalSingularFieldElement.constant(.originalDouble(bounds.upper, usage: &usage),
                in: t.context, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            if case .negative = try coordinate.subtracting(lower, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
                .sign(maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) { return nil }
            if case .positive = try coordinate.subtracting(upper, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
                .sign(maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) { return nil }
        }
        let mappedU = try chart.germ.originalU.evaluated(atU: x, v: y,
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        let mappedV = try chart.germ.originalV.evaluated(atU: x, v: y,
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        guard case .zero = try mappedU.subtracting(originalU, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            .sign(maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage),
            case .zero = try mappedV.subtracting(originalV, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            .sign(maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) else { return nil }
        return chart.freeAlongU ? x : y
    }
}
