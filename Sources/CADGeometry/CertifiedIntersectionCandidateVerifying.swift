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
}
