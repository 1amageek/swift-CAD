import CADCore

protocol CertifiedCylinderCylinderReductionEligibility: Sendable {
    func supportsCertifiedIntersection(
        first: CanonicalAnalyticSurface.Cylinder,
        second: CanonicalAnalyticSurface.Cylinder,
        tolerance: ModelingTolerance
    ) throws -> Bool
}
