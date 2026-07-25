import CADCore

protocol CertifiedCylinderCylinderReductionEligibility: Sendable {
    func supportsFullBranchIntersection(
        first: CanonicalAnalyticSurface.Cylinder,
        second: CanonicalAnalyticSurface.Cylinder,
        tolerance: ModelingTolerance
    ) throws -> Bool
}
