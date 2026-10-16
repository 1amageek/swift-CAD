import CADCore

/// Exact inversion of a retained silhouette's ORIGINAL parameter maps at a UV root.
struct SurfaceSilhouetteProjectedParameterInverse {
    static func parameters(at root: ExactBivariateSystemRoot, in context: OriginalSingularFieldContext,
        chart: SurfaceParameterBox, freeCoordinate: OriginalSurfaceSilhouetteCurve.FreeCoordinate,
        freeImage: SurfaceSilhouetteFreeParameterImage?, orderedImage: SurfaceSilhouetteOrderedFreeParameterImage?,
        cuspImage: SurfaceSilhouetteCuspParameterImage?, ramifiedImage: SurfaceSilhouetteRamifiedParameterImage?,
        usage: inout OriginalQueryExecution) throws -> [OriginalSingularFieldElement] {
        let u = try OriginalSingularFieldElement.original(.coordinate(alongU: true, usage: &usage), in: context, usage: &usage)
        let v = try OriginalSingularFieldElement.original(.coordinate(alongU: false, usage: &usage), in: context, usage: &usage)
        return try parameters(originalU: u, originalV: v, chart: chart, freeCoordinate: freeCoordinate,
            freeImage: freeImage, orderedImage: orderedImage, cuspImage: cuspImage,
            ramifiedImage: ramifiedImage, usage: &usage)
    }

    static func parameters(originalU u: OriginalSingularFieldElement, originalV v: OriginalSingularFieldElement,
        chart: SurfaceParameterBox, freeCoordinate: OriginalSurfaceSilhouetteCurve.FreeCoordinate,
        freeImage: SurfaceSilhouetteFreeParameterImage?, orderedImage: SurfaceSilhouetteOrderedFreeParameterImage?,
        cuspImage: SurfaceSilhouetteCuspParameterImage?, ramifiedImage: SurfaceSilhouetteRamifiedParameterImage?,
        usage: inout OriginalQueryExecution) throws -> [OriginalSingularFieldElement] {
        guard u.context === v.context else { throw rationalAlgebraFailure("Original UV inverse lost its shared real source field.") }
        let context = u.context
        for axis in 0..<2 {
            let coordinate = axis == 0 ? u : v
            let bounds = axis == 0 ? chart.u : chart.v
            let low = try coordinate.subtracting(.constant(.originalDouble(bounds.lower, usage: &usage),
                in: context, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage), maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            let high = try OriginalSingularFieldElement.constant(.originalDouble(bounds.upper, usage: &usage),
                in: context, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
                .subtracting(coordinate, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            if case .negative = try low.sign(maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) { return [] }
            if case .negative = try high.sign(maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) { return [] }
        }
        if let ramifiedImage {
            return try ramified(ramifiedImage, u: u, v: v, usage: &usage)
        }
        var free: [OriginalSingularFieldElement] = []
        if let cuspImage {
            let first = try rationalPolynomial(cuspImage.cusp.u, in: context, usage: &usage)
            let second = try rationalPolynomial(cuspImage.cusp.v, in: context, usage: &usage)
            let uConstant = try constantPolynomial(u, usage: &usage)
            let vConstant = try constantPolynomial(v, usage: &usage)
            let x = try first.subtracting(uConstant, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            let y = try second.subtracting(vConstant, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            let common = try OriginalSingularFieldPolynomial.gcd(x, y, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            guard !common.isZero else {
                throw rationalAlgebraFailure("Original cusp parameter map is not an isolated preimage authority.")
            }
            for parameter in try OriginalSingularFieldRoot.allRealRoots(common, inheritedDepth: context.depth,
                maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) {
                guard case .zero = try parameter.sign(of: x, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage),
                    case .zero = try parameter.sign(of: y, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) else {
                    throw rationalAlgebraFailure("Original cusp inverse violates an original UV map.")
                }
                let value = try parameter.value(maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
                try RationalAlgebraStorage.retain(1, of: OriginalSingularFieldElement.self, usage: &usage)
                free.append(value)
            }
        } else {
            try RationalAlgebraStorage.retain(1, of: OriginalSingularFieldElement.self, usage: &usage)
            free.append(freeCoordinate == .u ? u : v)
        }
        var result: [OriginalSingularFieldElement] = []
        for value in free {
            let parameter: OriginalSingularFieldElement
            if let orderedImage {
                parameter = try fraction(value, from: orderedImage.start.original,
                    to: orderedImage.end.original, usage: &usage)
            } else if let freeImage {
                let transport = OriginalSingularFieldTransport()
                let first = try transport.originalScalarValue(freeImage.start, into: value.context,
                    maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
                let last = try transport.originalScalarValue(freeImage.end, into: value.context,
                    maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
                parameter = try fraction(value, from: first, to: last, usage: &usage)
            } else { parameter = value }
            try RationalAlgebraStorage.retain(1, of: OriginalSingularFieldElement.self, usage: &usage)
            result.append(parameter)
        }
        return result
    }

    private static func fraction(_ value: OriginalSingularFieldElement,
        from lower: OriginalSingularFieldElement, to upper: OriginalSingularFieldElement,
        usage: inout OriginalQueryExecution) throws -> OriginalSingularFieldElement {
        var transport = OriginalSingularFieldTransport()
        var context = try transport.importing(lower.context, into: value.context,
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        context = try transport.importing(upper.context, into: context,
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        let original = try value.embedded(in: context, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        let first = try transport.applying(to: lower, in: context, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        let last = try transport.applying(to: upper, in: context, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        let gain = try last.subtracting(first, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        guard case .positive = try gain.sign(maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) else {
            throw rationalAlgebraFailure("Original silhouette inverse has no positive original traversal slope.")
        }
        return try original.subtracting(first, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            .divided(by: gain, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
    }

    private static func constantPolynomial(_ value: OriginalSingularFieldElement,
        usage: inout OriginalQueryExecution) throws -> OriginalSingularFieldPolynomial {
        try RationalAlgebraStorage.retain(1, of: OriginalSingularFieldElement.self, usage: &usage)
        return try .init(context: value.context, coefficients: [value], maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
    }

    private static func rationalPolynomial(_ original: ExactBivariatePolynomial,
        in context: OriginalSingularFieldContext, usage: inout OriginalQueryExecution)
        throws -> OriginalSingularFieldPolynomial {
        guard original.vDegree <= 0 else { throw rationalAlgebraFailure("Original parameter map is not univariate.") }
        let count = try rationalAlgebraCount(max(0, original.uDegree), 1)
        try RationalAlgebraStorage.retain(count, of: OriginalSingularFieldElement.self, usage: &usage)
        var values: [OriginalSingularFieldElement] = []; values.reserveCapacity(count)
        for degree in 0..<count {
            try usage.consumeWork(1)
            let coefficient = original.originalCoefficients[try .init(u: degree, v: 0)] ?? .zero
            values.append(try .constant(coefficient, in: context, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage))
        }
        return try .init(context: context, coefficients: values, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
    }

    private static func ramified(_ image: SurfaceSilhouetteRamifiedParameterImage,
        u: OriginalSingularFieldElement, v: OriginalSingularFieldElement,
        usage: inout OriginalQueryExecution) throws -> [OriginalSingularFieldElement] {
        var transport = OriginalSingularFieldTransport()
        let germ = image.original.germ
        let context = try transport.importing(germ.strictTransform.context, into: v.context,
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        func imported(_ original: OriginalSingularFieldPlanePolynomial, usage: inout OriginalQueryExecution)
            throws -> OriginalSingularFieldPlanePolynomial {
            try RationalAlgebraStorage.retain(original.coefficients.count,
                of: (ExactBivariatePolynomial.Power, OriginalSingularFieldElement).self, usage: &usage)
            var values: [ExactBivariatePolynomial.Power: OriginalSingularFieldElement] = [:]
            for (power, coefficient) in try original.orderedTerms(usage: &usage) {
                values[power] = try transport.applying(to: coefficient, in: context,
                    maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            }
            return try .init(context: context, coefficients: values, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        }
        let x = try u.embedded(in: context, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        let y = try v.embedded(in: context, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        let strict = try imported(germ.strictTransform, usage: &usage)
        let first = try imported(germ.originalU, usage: &usage)
            .subtracting(.constant(x, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage), maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        let second = try imported(germ.originalV, usage: &usage)
            .subtracting(.constant(y, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage), maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        try RationalAlgebraStorage.retain(3, of: OriginalSingularFieldPlanePolynomial.self, usage: &usage)
        let outcome = try OriginalSingularFieldSystemSolver.roots(of: [strict, first, second],
            over: image.original.localDomain, inheritedDepth: max(context.depth, image.original.sourceDepth),
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        guard case .finite(let roots) = outcome else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): A production projected contact
            // at a nullified resolution map requires its complete retained exceptional
            // fiber. A positive-dimensional inverse must not become no contact.
            throw rationalAlgebraFailure("Original ramified inverse retained an unresolved exceptional fiber.")
        }
        var values: [OriginalSingularFieldElement] = []
        for root in roots {
            let free = image.original.freeAlongU ? root.u : root.v
            let lower: OriginalSingularFieldElement, upper: OriginalSingularFieldElement
            if let start = image.retainedStart, let end = image.retainedEnd { lower = start; upper = end }
            else {
                func endpoint(_ original: OriginalSingularFieldEndpoint) throws -> OriginalSingularFieldElement {
                    switch original {
                    case .authored(let coefficient): return try .constant(coefficient, in: free.context,
                        maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
                    case .algebraic(let root): return try root.value(maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
                    }
                }
                lower = try endpoint(image.start); upper = try endpoint(image.end)
            }
            let parameter = try fraction(free, from: lower, to: upper, usage: &usage)
            try RationalAlgebraStorage.retain(1, of: OriginalSingularFieldElement.self, usage: &usage)
            values.append(parameter)
        }
        return values
    }
}
