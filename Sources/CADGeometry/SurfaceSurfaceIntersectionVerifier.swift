import CADCore

struct SurfaceSurfaceIntersectionVerifier {
    static let lineSamples = [-1.0, 0.0, 1.0]
    static let closedCurveSamples = [0.0, Double.pi * 0.5, Double.pi, Double.pi * 1.5]

    // FIXME(INCOMPLETE_IMPLEMENTATION): Direct plane/legacy SSI publication calls
    // this gate. Sampled residuals do not establish an original common set;
    // U4 must provide complete original source/UV proof before this port succeeds.
    func curve(
        _ curve: Curve3D,
        kind: CurveSurfaceIntersectionKind,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        sampleParameters: [Double],
        firstParameterCurve: SurfaceParameterCurve? = nil,
        secondParameterCurve: SurfaceParameterCurve? = nil,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> SurfaceSurfaceIntersection {
        execution.context = execution.context.at(stage: .publication)
        do {
            try execution.checkpoint()
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Original surface intersection publication requires source-bound proof authority.")
        } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance) }
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Existing analytic candidate/source helpers
    // still reference this ordinary publication port. The former sampled success
    // implementation is removed; U4 requires source-bound proof and direct execution.
    func curve(
        _ curve: Curve3D,
        kind: CurveSurfaceIntersectionKind,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        sampleParameters: [Double],
        firstParameterCurve: SurfaceParameterCurve? = nil,
        secondParameterCurve: SurfaceParameterCurve? = nil,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        try CurrentTaskCancellationChecker().checkCancellation()
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "An ordinary sampled verifier cannot publish original intersection truth.")
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Direct plane/legacy SSI publication calls
    // this gate. Sampled residuals do not establish an original common set;
    // U4 must provide complete original source/UV proof before this port succeeds.
    func point(
        _ point: Point3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> SurfaceSurfaceIntersection {
        execution.context = execution.context.at(stage: .publication)
        do {
            try execution.checkpoint()
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Original surface intersection publication requires source-bound proof authority.")
        } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance) }
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Existing analytic candidate/source helpers
    // still reference this ordinary publication port. The former sampled success
    // implementation is removed; U4 requires source-bound proof and direct execution.
    func point(
        _ point: Point3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        try CurrentTaskCancellationChecker().checkCancellation()
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "An ordinary sampled verifier cannot publish original intersection truth.")
    }

}
