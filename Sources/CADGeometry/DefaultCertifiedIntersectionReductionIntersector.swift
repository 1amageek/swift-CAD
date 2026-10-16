import CADCore

struct DefaultCertifiedIntersectionReductionIntersector: CertifiedIntersectionReductionIntersecting {
    func intersections(
        curve: CertifiedIntersectionCurve3D,
        targetSurface: Surface3D,
        reduction: CertifiedIntersectionReduction,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        sectionCurveIntersector: any CurveSurfaceIntersecting
    ) throws -> [CurveSurfaceIntersection] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try intersections(curve: curve, targetSurface: targetSurface, reduction: reduction, options: options, tolerance: tolerance, sectionCurveIntersector: sectionCurveIntersector, using: &execution)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): This callable general CS route has no
    // complete original root, exclusion and parameter-domain coverage issuer.
    // Residual candidates cannot publish success, absence or coincidence; U4
    // must supply that authority before this family can be reported complete.
    func intersections(
        curve: CertifiedIntersectionCurve3D,
        targetSurface: Surface3D,
        reduction: CertifiedIntersectionReduction,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        sectionCurveIntersector: any CurveSurfaceIntersecting,
        using execution: inout OriginalQueryExecution
    ) throws -> [CurveSurfaceIntersection] {
        try execution.checkpoint()
        execution.context = execution.context.at(stage: .relation)
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "CertifiedIntersectionReduction requires complete original source and parameter coverage.")
    }
}
