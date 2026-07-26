import CADCore

protocol CertifiedImplicitCurveAnalyticSurfaceIntersecting: Sendable {
    func intersections(
        curve: CertifiedImplicitIntersectionCurve,
        targetSurface: Surface3D,
        canonicalTarget: CanonicalAnalyticSurface,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        rationalSurfaceIntersector: any CurveSurfaceIntersecting
    ) throws -> [CurveSurfaceIntersection]
}
