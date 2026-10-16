import CADCore

struct ParallelOffsetTorusTorusSurfaceIntersector {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Ordinary SSI dispatch reaches this direct entry.
    // The former numerical/tolerance branches did not establish original common-set
    // authority. U4 must supply complete original source/UV coverage before success.
    func intersections(
        first: CanonicalAnalyticSurface.Torus,
        second: CanonicalAnalyticSurface.Torus,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> [SurfaceSurfaceIntersection] {
        execution.context = execution.context.at(stage: .relation)
        do {
            try execution.checkpoint()
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "ParallelOffsetTorusTorusSurfaceIntersector requires complete original source relation authority.")
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
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        try CurrentTaskCancellationChecker().checkCancellation()
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "ParallelOffsetTorusTorusSurfaceIntersector has no ordinary original-proof publication.")
    }

    private func exactIntersection(
        proceduralCurve: CertifiedParallelTorusTorusIntersectionCurve,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        let truth = try CertifiedAnalyticAnalyticIntersectionCurve(
            parallelTorusTorusCurve: proceduralCurve,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
        let point = try truth.point(
            atNormalizedFraction: 0.0,
            tolerance: tolerance
        )
        let firstParameter = try truth.internalParameter(
            for: .first,
            atNormalizedFraction: 0.0,
            tolerance: tolerance
        )
        let secondParameter = try truth.internalParameter(
            for: .second,
            atNormalizedFraction: 0.0,
            tolerance: tolerance
        )
        return .curve(try SurfaceSurfaceIntersectionCurve(
            truth: .analyticAnalytic(truth),
            derivedRepresentation: try SurfaceSurfaceIntersectionDerivedRepresentation(
                curve: truth.curve,
                firstSurfaceParameterCurve: truth.firstSurfaceParameterCurve,
                secondSurfaceParameterCurve: truth.secondSurfaceParameterCurve,
                maximumResidualUpperBound:
                    proceduralCurve.maximumResidualUpperBound,
                tolerance: tolerance
            ),
            kind: .mixed,
            firstSurfaceAnchor: try SurfaceParameterProjection(
                u: firstParameter.u,
                v: firstParameter.v,
                point: point,
                residual: proceduralCurve.maximumResidualUpperBound
            ),
            secondSurfaceAnchor: try SurfaceParameterProjection(
                u: secondParameter.u,
                v: secondParameter.v,
                point: point,
                residual: proceduralCurve.maximumResidualUpperBound
            ),
            tolerance: tolerance
        ))
    }

    private func certifiedIntersection(
        _ derived: SurfaceSurfaceIntersection,
        proceduralCurve: CertifiedParallelTorusTorusIntersectionCurve,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        guard case let .curve(derivedCurve) = derived else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "A certified parallel torus-torus component did not produce a derived curve cache."
            )
        }
        let truth = try CertifiedAnalyticAnalyticIntersectionCurve(
            parallelTorusTorusCurve: proceduralCurve,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
        return .curve(try SurfaceSurfaceIntersectionCurve(
            truth: .analyticAnalytic(truth),
            derivedRepresentation: derivedCurve.derivedRepresentation,
            kind: derivedCurve.kind,
            firstSurfaceAnchor: derivedCurve.firstSurfaceAnchor,
            secondSurfaceAnchor: derivedCurve.secondSurfaceAnchor,
            tolerance: tolerance
        ))
    }
}
