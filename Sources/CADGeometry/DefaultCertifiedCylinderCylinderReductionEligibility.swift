import CADCore

struct DefaultCertifiedCylinderCylinderReductionEligibility:
    CertifiedCylinderCylinderReductionEligibility
{
    func supportsFullBranchIntersection(
        first: CanonicalAnalyticSurface.Cylinder,
        second: CanonicalAnalyticSurface.Cylinder,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        try GeneralCylinderCylinderSurfaceIntersector()
            .supportsFullBranchIntersections(
                first: first,
                second: second,
                tolerance: tolerance
            )
    }
}
