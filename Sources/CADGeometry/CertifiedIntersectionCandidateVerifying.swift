import CADCore

protocol CertifiedIntersectionCandidateVerifying: Sendable {
    func intersections(
        candidates: [CertifiedIntersectionCandidate],
        curve: CertifiedIntersectionCurve3D,
        targetSurface: Surface3D,
        analyticTarget: CertifiedAnalyticIntersectionTarget,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CurveSurfaceIntersection]

    func intersections(candidates: [CertifiedIntersectionCandidate], curve: CertifiedIntersectionCurve3D,
        targetSurface: Surface3D, analyticTarget: CertifiedAnalyticIntersectionTarget,
        options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> [CurveSurfaceIntersection]
}

extension CertifiedIntersectionCandidateVerifying {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Injected numerical candidate verifiers
    // must supply retained original relation authority and same-execution work
    // before this admitted requirement can publish complete events.
    func intersections(candidates: [CertifiedIntersectionCandidate], curve: CertifiedIntersectionCurve3D,
        targetSurface: Surface3D, analyticTarget: CertifiedAnalyticIntersectionTarget,
        options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> [CurveSurfaceIntersection] {
        try execution.checkpoint()
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "This candidate verifier has no direct original relation witness.")
    }
}
