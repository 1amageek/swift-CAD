import CADCore

protocol CertifiedIntersectionSpatialDisjointnessResolving: Sendable {
    func areDisjoint(
        curve: CertifiedIntersectionCurve3D,
        target: CanonicalAnalyticSurface,
        tolerance: ModelingTolerance
    ) throws -> Bool
}
