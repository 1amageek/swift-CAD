import CADCore

struct PlaneBSplineSurfaceIntersector {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Ordinary SSI dispatch reaches this direct entry.
    // The former numerical/tolerance branches did not establish original common-set
    // authority. U4 must supply complete original source/UV coverage before success.
    func intersections(
        plane: CanonicalAnalyticSurface.Plane,
        surface: BSplineSurface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        planeIsFirst: Bool,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> [SurfaceSurfaceIntersection] {
        execution.context = execution.context.at(stage: .relation)
        do {
            try execution.checkpoint()
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "PlaneBSplineSurfaceIntersector requires complete original source relation authority.")
        } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance) }
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Existing candidate/source helper methods call
    // this ordinary publication entry. It performs no numeric solve or fallback;
    // U4 must provide source-bound relation proof and direct execution before success.
    func intersections(
        plane: CanonicalAnalyticSurface.Plane,
        surface: BSplineSurface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        planeIsFirst: Bool,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        try CurrentTaskCancellationChecker().checkCancellation()
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "PlaneBSplineSurfaceIntersector has no ordinary original-proof publication.")
    }
}
