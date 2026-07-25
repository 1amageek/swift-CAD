import CADCore

protocol CertifiedReducedSectionIntersectionBoundResolving: Sendable {
    func isolatedIntersectionUpperBound(
        curve: CertifiedIntersectionCurve3D,
        targetSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Int
}
