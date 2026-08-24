import CADCore

/// Resolves the finite linear intersection produced when the cylinder axis is
/// parallel to a cone ruling.
///
/// The usual quadratic height coefficient vanishes in this configuration.
/// A complete finite component still exists when the remaining linear
/// coefficient is bounded away from zero for the full angular domain.
struct ConeCylinderRulingParallelIntersector {
    func intersectionsIfApplicable(
        coneSurface: Surface3D,
        cylinderSurface: Surface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection]? {
        guard let proceduralCurve = try CertifiedConeCylinderIntersectionCurve
            .rulingParallelLinearCurveIfApplicable(
                coneSurface: coneSurface,
                cylinderSurface: cylinderSurface,
                tolerance: tolerance
            ) else {
            return nil
        }
        let builder = SurfaceIntersectionSplineBuilder(
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            options: options,
            tolerance: tolerance
        )
        let evaluationContext = SurfaceIntersectionCurveEvaluationContext(
            curve: proceduralCurve,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
        let derived = try builder.intersection(
            parameterRange: 0.0...1.0,
            initialBreaks: (0...16).map { Double($0) / 16.0 },
            kind: .transverse,
            firstParameterAt: { fraction in
                try evaluationContext.firstParameter(at: fraction)
            },
            secondParameterAt: { fraction in
                try evaluationContext.secondParameter(at: fraction)
            },
            pointAt: { fraction in
                try evaluationContext.point(at: fraction)
            }
        )
        guard case let .curve(derivedCurve) = derived else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "A ruling-parallel cone-cylinder component did not produce a derived curve cache."
            )
        }
        let truth = try CertifiedAnalyticAnalyticIntersectionCurve(
            coneCylinderCurve: proceduralCurve,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
        return [.curve(try SurfaceSurfaceIntersectionCurve(
            truth: .analyticAnalytic(truth),
            derivedRepresentation: derivedCurve.derivedRepresentation,
            kind: derivedCurve.kind,
            firstSurfaceAnchor: derivedCurve.firstSurfaceAnchor,
            secondSurfaceAnchor: derivedCurve.secondSurfaceAnchor,
            tolerance: tolerance
        ))]
    }
}
