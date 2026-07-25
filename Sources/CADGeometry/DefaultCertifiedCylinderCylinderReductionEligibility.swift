import CADCore

struct DefaultCertifiedCylinderCylinderReductionEligibility:
    CertifiedCylinderCylinderReductionEligibility
{
    func supportsCertifiedIntersection(
        first: CanonicalAnalyticSurface.Cylinder,
        second: CanonicalAnalyticSurface.Cylinder,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        try GeneralCylinderCylinderSurfaceIntersector()
            .supportsCertifiedIntersections(
                first: first,
                second: second,
                tolerance: tolerance
            )
    }
}
