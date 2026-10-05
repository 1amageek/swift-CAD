import CADCore

extension OriginalCurveCurveContact {
    /// Consumes the retained native scalar root; never rounds its parameter.
    package func firstNativeEndpoint(allowance: inout OriginalCurveContactAllowance) throws
        -> OriginalCurveRootEndpoint? {
        // FIXME(INCOMPLETE_IMPLEMENTATION): General original angular and
        // implicit guide events still need their own persistent scalar recipe.
        // This native root issuer must not infer such a recipe from a numerical
        // contact bracket or alias it to a B-spline construction parameter.
        guard let parameterAuthority, let index = firstNativeSpanIndex,
            case .bSpline(let source) = firstSource.curve else { return nil }
        let policy = allowance.budget.enterExactAlgebra()
        defer { allowance.budget.restoreExactAlgebra(policy) }
        let depth = allowance.budget.maximumAlgebraicDepth
        let root: ExactAlgebraicRealRoot
        switch parameterAuthority.originalRoot {
        case .rational(let pair): root = pair.projectionRoot
        case .field(let pair):
            let coordinate = try OriginalSingularRationalCoordinateRoot(original: pair.u,
                maximumDepth: depth, maximumAlgebraicDepth: depth, usage: &allowance.budget)
            switch coordinate.endpoint {
            case .algebraic(let retained): root = retained
            case .authored(let station):
                let bounds = try station.outwardInterval(usage: &allowance.budget)
                guard bounds.lower == bounds.upper else {
                    throw KernelError(phase: .geometry, code: .classificationFailure, tolerance: tolerance,
                        message: "Original field scalar endpoint issuer omitted its nonrepresentable retained root.")
                }
                return .authored(bounds.lower)
            }
        }
        let original = try OriginalRationalCurvePolynomial(source: source, spanIndex: index,
            tolerance: tolerance, usage: &allowance.budget)
        for station in [source.knots[index], source.knots[index+1]] {
            let equation = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &allowance.budget)
                .subtracting(.constant(.originalDouble(station, usage: &allowance.budget),
                    usage: &allowance.budget), usage: &allowance.budget)
            if case .zero = try root.sign(of: equation, maximumDepth: depth, usage: &allowance.budget) {
                return .authored(station)
            }
        }
        var retained = root
        var width = try original.upperParameter.subtracting(original.lowerParameter, usage: &allowance.budget)
        let two = try ExactRationalCoefficient.natural(2, usage: &allowance.budget)
        while try retained.isolation.lower.subtracting(original.lowerParameter, usage: &allowance.budget).isNegative
            || original.upperParameter.subtracting(retained.isolation.upper, usage: &allowance.budget).isNegative {
            width = try width.divided(by: two, usage: &allowance.budget)
            retained = try retained.refined(maximumWidth: width, maximumDepth: depth, usage: &allowance.budget)
        }
        return try .algebraic(OriginalCurveRootBoundary.retaining(prepared: original, coordinate: retained,
            maximumSubdivisionDepth: allowance.maximumSubdivisionDepth, tolerance: tolerance,
            usage: &allowance.budget, maximumAlgebraicDepth: depth))
    }
}
