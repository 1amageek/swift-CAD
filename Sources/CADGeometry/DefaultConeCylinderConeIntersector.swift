import CADCore

struct DefaultConeCylinderConeIntersector: ConeCylinderConeIntersecting {
    func supports(
        curve: CertifiedConeCylinderIntersectionCurve,
        coneSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try supports(curve: curve, coneSurface: coneSurface, tolerance: tolerance, using: &execution)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): This callable general CS route has no
    // complete original root, exclusion and parameter-domain coverage issuer.
    // Residual candidates cannot publish success, absence or coincidence; U4
    // must supply that authority before this family can be reported complete.
    func supports(
        curve: CertifiedConeCylinderIntersectionCurve,
        coneSurface: Surface3D,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> Bool {
        try execution.checkpoint()
        return false
    }

    func intersections(
        curve: CertifiedConeCylinderIntersectionCurve,
        coneSurface: Surface3D,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CurveSurfaceIntersection] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try intersections(curve: curve, coneSurface: coneSurface, options: options, tolerance: tolerance, using: &execution)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): This callable general CS route has no
    // complete original root, exclusion and parameter-domain coverage issuer.
    // Residual candidates cannot publish success, absence or coincidence; U4
    // must supply that authority before this family can be reported complete.
    func intersections(
        curve: CertifiedConeCylinderIntersectionCurve,
        coneSurface: Surface3D,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> [CurveSurfaceIntersection] {
        try execution.checkpoint()
        execution.context = execution.context.at(stage: .relation)
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "ConeCylinderCone requires complete original source and parameter coverage.")
    }
}
