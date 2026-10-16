import CADCore

struct DefaultCertifiedIntersectionCandidateVerifier: CertifiedIntersectionCandidateVerifying {
    init() {}

    func intersections(candidates: [CertifiedIntersectionCandidate], curve: CertifiedIntersectionCurve3D,
        targetSurface: Surface3D, analyticTarget: CertifiedAnalyticIntersectionTarget,
        options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance) throws -> [CurveSurfaceIntersection] {
        var execution = try OriginalQueryExecution.curveSurface(options: options)
        return try intersections(candidates: candidates, curve: curve, targetSurface: targetSurface,
            analyticTarget: analyticTarget, options: options, tolerance: tolerance, using: &execution)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Legacy candidate-verifier callers supply
    // numerical points and residuals without a retained original relation. Exact
    // source/domain coverage and parameter identity must be supplied before this
    // entry may publish an intersection event or complete empty result.
    func intersections(candidates: [CertifiedIntersectionCandidate], curve: CertifiedIntersectionCurve3D,
        targetSurface: Surface3D, analyticTarget: CertifiedAnalyticIntersectionTarget,
        options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> [CurveSurfaceIntersection] {
        try execution.checkpoint()
        try options.validate(tolerance: tolerance)
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "Numerical intersection candidates have no retained original relation authority.")
    }
}
