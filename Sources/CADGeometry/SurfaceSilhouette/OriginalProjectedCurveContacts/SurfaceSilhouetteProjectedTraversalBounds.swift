import CADCore

/// Original native free-coordinate cuts corresponding to exact traversal trim endpoints.
struct SurfaceSilhouetteProjectedTraversalBounds {
    static func nativeFree(_ parameter: OriginalSingularFieldElement,
        authority: (polynomial: ExactBivariatePolynomial?, fieldPolynomial: OriginalSingularFieldPlanePolynomial?,
            image: SurfaceSilhouetteFreeParameterImage?, orderedImage: SurfaceSilhouetteOrderedFreeParameterImage?,
            cusp: SurfaceSilhouetteCuspParameterImage?, ramified: SurfaceSilhouetteRamifiedParameterImage?),
        alongU: Bool, usage: inout OriginalQueryExecution) throws -> OriginalSingularFieldElement {
        if let ramified = authority.ramified {
            let start: OriginalSingularFieldElement, end: OriginalSingularFieldElement
            if let first = ramified.retainedStart, let last = ramified.retainedEnd {
                start = first; end = last
            } else {
                func value(_ endpoint: OriginalSingularFieldEndpoint) throws -> OriginalSingularFieldElement {
                    switch endpoint {
                    case .authored(let coefficient): return try .constant(coefficient, in: parameter.context,
                        maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
                    case .algebraic(let root): return try root.value(maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
                    }
                }
                start = try value(ramified.start); end = try value(ramified.end)
            }
            let free = try mapped(parameter, start: start, end: end, usage: &usage)
            return try ramifiedCoordinate(free, image: ramified, alongU: alongU, usage: &usage)
        }
        let native: OriginalSingularFieldElement
        if let image = authority.orderedImage {
            native = try mapped(parameter, start: image.start.original, end: image.end.original, usage: &usage)
        } else if let image = authority.image {
            let transport = OriginalSingularFieldTransport()
            let start = try transport.originalScalarValue(image.start, into: parameter.context,
                maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            let end = try transport.originalScalarValue(image.end, into: start.context,
                maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            native = try mapped(parameter, start: start, end: end, usage: &usage)
        } else { native = parameter }
        if let cusp = authority.cusp {
            return try rationalValue(alongU ? cusp.cusp.u : cusp.cusp.v, at: native, usage: &usage)
        }
        return native
    }

    private static func mapped(_ parameter: OriginalSingularFieldElement, start: OriginalSingularFieldElement,
        end: OriginalSingularFieldElement, usage: inout OriginalQueryExecution) throws -> OriginalSingularFieldElement {
        var transport = OriginalSingularFieldTransport()
        var context = try transport.importing(start.context, into: parameter.context,
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        context = try transport.importing(end.context, into: context, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        let first = try transport.applying(to: start, in: context, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        let last = try transport.applying(to: end, in: context, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        let t = try parameter.embedded(in: context, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        return try first.adding(last.subtracting(first, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            .multiplied(by: t, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage), maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
    }

    private static func rationalValue(_ polynomial: ExactBivariatePolynomial,
        at parameter: OriginalSingularFieldElement, usage: inout OriginalQueryExecution) throws -> OriginalSingularFieldElement {
        guard polynomial.vDegree <= 0 else { throw rationalAlgebraFailure("Original cusp free map is not a scalar polynomial.") }
        var result = try OriginalSingularFieldElement.constant(.zero, in: parameter.context,
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        if polynomial.uDegree >= 0 { for index in (0...polynomial.uDegree).reversed() {
            let coefficient = polynomial.originalCoefficients[try .init(u: index, v: 0)] ?? .zero
            result = try result.multiplied(by: parameter, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
                .adding(.constant(coefficient, in: parameter.context, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage),
                    maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        } }
        return result
    }

    private static func ramifiedCoordinate(_ free: OriginalSingularFieldElement,
        image: SurfaceSilhouetteRamifiedParameterImage, alongU: Bool,
        usage: inout OriginalQueryExecution) throws -> OriginalSingularFieldElement {
        var transport = OriginalSingularFieldTransport()
        let context = try transport.importing(image.original.germ.strictTransform.context, into: free.context,
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        let t = try free.embedded(in: context, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        let original = image.original.germ.strictTransform
        let transverseDegree = image.original.freeAlongU ? original.vDegree : original.uDegree
        let count = try rationalAlgebraCount(max(0, transverseDegree), 1)
        try RationalAlgebraStorage.retain(count, of: OriginalSingularFieldElement.self, usage: &usage)
        let zero = try OriginalSingularFieldElement.constant(.zero, in: context,
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        var coefficients = [OriginalSingularFieldElement](repeating: zero, count: count)
        for (power, value) in try original.orderedTerms(usage: &usage) {
            let freePower = image.original.freeAlongU ? power.u : power.v
            let transversePower = image.original.freeAlongU ? power.v : power.u
            var coefficient = try transport.applying(to: value, in: context,
                maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            for _ in 0..<freePower { coefficient = try coefficient.multiplied(by: t,
                maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) }
            coefficients[transversePower] = try coefficients[transversePower].adding(coefficient,
                maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        }
        let equation = try OriginalSingularFieldPolynomial(context: context, coefficients: coefficients,
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        guard !equation.isZero else { throw rationalAlgebraFailure("Original ramified forward graph has a nullified unique fiber.") }
        let domain = image.original.freeAlongU ? image.original.localDomain.v : image.original.localDomain.u
        var selected: OriginalSingularFieldElement?
        for root in try OriginalSingularFieldRoot.allRealRoots(equation,
            inheritedDepth: max(context.depth, image.refinementDepth), maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) {
            let value = try root.value(maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            let low = try value.subtracting(.constant(.originalDouble(domain.lower, usage: &usage), in: value.context,
                maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage), maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            let high = try OriginalSingularFieldElement.constant(.originalDouble(domain.upper, usage: &usage), in: value.context,
                maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage).subtracting(value, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            if case .negative = try low.sign(maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) { continue }
            if case .negative = try high.sign(maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) { continue }
            if case .some = selected { throw rationalAlgebraFailure("Original ramified graph contradicts transverse uniqueness.") }
            selected = value
        }
        guard let selected else { throw rationalAlgebraFailure("Original ramified endpoint has no source graph fiber.") }
        let scalar = try t.embedded(in: selected.context, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        let u = image.original.freeAlongU ? scalar : selected
        let v = image.original.freeAlongU ? selected : scalar
        let map = alongU ? image.original.germ.originalU : image.original.germ.originalV
        var result = try OriginalSingularFieldElement.constant(.zero, in: selected.context,
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        for (power, coefficient) in try map.orderedTerms(usage: &usage) {
            var term = try transport.applying(to: coefficient, in: selected.context,
                maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            for _ in 0..<power.u { term = try term.multiplied(by: u, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) }
            for _ in 0..<power.v { term = try term.multiplied(by: v, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) }
            result = try result.adding(term, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        }
        return result
    }
}
