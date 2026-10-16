import CADCore

struct DefaultCertifiedImplicitCurveAnalyticSurfaceIntersector: CertifiedImplicitCurveAnalyticSurfaceIntersecting {
    func intersections(
        curve: CertifiedImplicitIntersectionCurve,
        targetSurface: Surface3D,
        canonicalTarget: CanonicalAnalyticSurface,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        rationalSurfaceIntersector: any CurveSurfaceIntersecting
    ) throws -> [CurveSurfaceIntersection] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try intersections(curve: curve, targetSurface: targetSurface, canonicalTarget: canonicalTarget, options: options, tolerance: tolerance, rationalSurfaceIntersector: rationalSurfaceIntersector, using: &execution)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): This callable general CS route has no
    // complete original root, exclusion and parameter-domain coverage issuer.
    // Residual candidates cannot publish success, absence or coincidence; U4
    // must supply that authority before this family can be reported complete.
    func intersections(
        curve: CertifiedImplicitIntersectionCurve,
        targetSurface: Surface3D,
        canonicalTarget: CanonicalAnalyticSurface,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        rationalSurfaceIntersector: any CurveSurfaceIntersecting,
        using execution: inout OriginalQueryExecution
    ) throws -> [CurveSurfaceIntersection] {
        try execution.checkpoint()
        execution.context = execution.context.at(stage: .relation)
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "CertifiedImplicitCurveAnalyticSurface requires complete original source and parameter coverage.")
    }
}
