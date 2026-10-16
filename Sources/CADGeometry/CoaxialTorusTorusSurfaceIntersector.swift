import CADCore

struct CoaxialTorusTorusSurfaceIntersector {
    private let verifier = SurfaceSurfaceIntersectionVerifier()

    // FIXME(INCOMPLETE_IMPLEMENTATION): Ordinary SSI dispatch reaches this direct entry.
    // The former numerical/tolerance branches did not establish original common-set
    // authority. U4 must supply complete original source/UV coverage before success.
    func intersections(
        first: CanonicalAnalyticSurface.Torus,
        second: CanonicalAnalyticSurface.Torus,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> [SurfaceSurfaceIntersection] {
        execution.context = execution.context.at(stage: .relation)
        do {
            try execution.checkpoint()
            try execution.consumeWork(1)
            if case .analytic = firstSurface, case .analytic = secondSurface,
                firstSurface == secondSurface {
                try firstSurface.validateOriginalSource(tolerance: tolerance,
                    remainingSourceDepth: execution.limits.remainingSourceDepth,
                    maximumSubdivisionDepth: execution.limits.maximumSubdivisionDepth, using: &execution)
                try execution.retainStorage(bytes: MemoryLayout<SurfaceSurfaceIntersection>.stride)
                let result: [SurfaceSurfaceIntersection] = [.coincident(try .init(residual: 0, tolerance: tolerance))]
                try execution.checkpoint()
                return result
            }
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "CoaxialTorusTorusSurfaceIntersector requires complete original source relation authority.")
        } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance) }
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Existing candidate/source helper methods call
    // this ordinary publication entry. It performs no numeric solve or fallback;
    // U4 must provide source-bound relation proof and direct execution before success.
    func intersections(
        first: CanonicalAnalyticSurface.Torus,
        second: CanonicalAnalyticSurface.Torus,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        try CurrentTaskCancellationChecker().checkCancellation()
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "CoaxialTorusTorusSurfaceIntersector has no ordinary original-proof publication.")
    }

    private func unsupported(
        residual: Double,
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .invalidInput,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }
}
