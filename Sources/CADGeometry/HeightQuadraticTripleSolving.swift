import CADCore

protocol HeightQuadraticTripleSolving: Sendable {
    func supports(
        context: any HeightQuadraticIntersectionContext,
        tolerance: ModelingTolerance
    ) -> Bool

    func candidates(
        context: any HeightQuadraticIntersectionContext,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CertifiedIntersectionCandidate]
}
