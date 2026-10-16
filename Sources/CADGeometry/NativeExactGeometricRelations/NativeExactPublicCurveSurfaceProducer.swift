import CADCore

/// Selects one source-bound L5/L6 solve under the original public caller execution.
struct NativeExactPublicCurveSurfaceProducer {
    func resolve(curve: Curve3D, surface: Surface3D, options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, retainingRelations: Bool = false,
        using usage: inout OriginalQueryExecution) throws -> CurveSurfaceIntersectionResult? {
        // Decide the canonical Native family before spending the original caller budget.
        // Unsupported families retain their existing issuer's complete caller budget.
        guard case .bSpline(let source) = curve, case .bSpline(let target) = surface,
            !source.isPeriodic, !target.isUPeriodic, !target.isVPeriodic,
            source.degree >= 0, source.degree < Int.max - 1,
            target.uDegree >= 0, target.uDegree < Int.max - 1,
            target.vDegree >= 0, target.vDegree < Int.max - 1,
            source.controlPointCount == source.degree + 1,
            target.uControlPointCount == target.uDegree + 1,
            target.vControlPointCount == target.vDegree + 1 else { return nil }
        do {
            try options.validate(tolerance: tolerance)
            usage.context = usage.context.at(stage: .source)
            try usage.consumeWork(1)
            guard usage.effectiveLimits.remainingSourceDepth > 0 else {
                throw failure(.resourceLimitExceeded, "Native exact preparation exhausted original source depth.", tolerance)
            }
            guard max(source.degree, target.uDegree, target.vDegree) <= options.maximumPolynomialDegree else {
                throw failure(.resourceLimitExceeded, "Native exact source degree exceeds the admitted ceiling.", tolerance)
            }
            try source.validate(tolerance: tolerance, using: &usage)
            try target.validate(tolerance: tolerance, using: &usage)
            try requireSingleSpan(source.knots, degree: source.degree, tolerance: tolerance, usage: &usage)
            try requireSingleSpan(target.uKnots, degree: target.uDegree, tolerance: tolerance, usage: &usage)
            try requireSingleSpan(target.vKnots, degree: target.vDegree, tolerance: tolerance, usage: &usage)
            let maximumSpans = min(usage.effectiveLimits.maximumNativeSpans ?? usage.effectiveLimits.maximumSpans, 262_144)
            guard maximumSpans >= 1 else {
                throw failure(.resourceLimitExceeded, "Native exact product exceeds the cumulative span ceiling.", tolerance)
            }
            usage.context = usage.context.at(stage: .relation)
            let result = try NativeExactCurveSurfacePointProducer().resolve(curve: source, surface: target,
                options: options, tolerance: tolerance, maximumExtensionLevel: Int.max,
                limits: NativeExactPublicLimits.unboundedStructure(), using: &usage)
            guard retainingRelations || !result.hasPositiveDimensionalSolutions else {
                throw failure(.nonDiscreteIntersection,
                    "The original requested native product contains a positive-dimensional intersection.", tolerance)
            }
            try usage.checkpoint()
            return result
        } catch { throw NativeExactGeometryPublicationFailure.published(error, tolerance: tolerance, context: usage.context) }
    }

    private func requireSingleSpan(_ knots: [Double], degree: Int, tolerance: ModelingTolerance,
        usage: inout OriginalQueryExecution) throws {
        try usage.consumeWork(1)
        guard degree >= 0, degree < Int.max / 2, knots.count == 2 * (degree + 1),
            knots.indices.contains(degree + 1) else {
            throw failure(.invalidInput, "Native exact CS requires its complete original single-span knot source.", tolerance)
        }
        let lower = knots[degree], upper = knots[degree + 1]
        guard lower.isFinite, upper.isFinite, lower < upper else {
            throw failure(.invalidInput, "Native exact CS requires a finite positive original knot span.", tolerance)
        }
    }

    private func failure(_ code: KernelErrorCode, _ message: String,
        _ tolerance: ModelingTolerance) -> KernelError {
        .init(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
