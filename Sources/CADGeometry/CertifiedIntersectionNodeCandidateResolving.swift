import CADCore

protocol CertifiedIntersectionNodeCandidateResolving: Sendable {
    func candidates(
        curve: CertifiedIntersectionCurve3D,
        targetSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [CertifiedIntersectionCandidate]
}
