import CADCore

struct DefaultConeCylinderSphereIntersector: ConeCylinderSphereIntersecting {
    func intersections(
        curve: CertifiedConeCylinderIntersectionCurve,
        sphereSurface: Surface3D,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CurveSurfaceIntersection] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try intersections(curve: curve, sphereSurface: sphereSurface, options: options, tolerance: tolerance, using: &execution)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): This callable general CS route has no
    // complete original root, exclusion and parameter-domain coverage issuer.
    // Residual candidates cannot publish success, absence or coincidence; U4
    // must supply that authority before this family can be reported complete.
    func intersections(
        curve: CertifiedConeCylinderIntersectionCurve,
        sphereSurface: Surface3D,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> [CurveSurfaceIntersection] {
        try execution.checkpoint()
        execution.context = execution.context.at(stage: .relation)
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "ConeCylinderSphere requires complete original source and parameter coverage.")
    }
}
