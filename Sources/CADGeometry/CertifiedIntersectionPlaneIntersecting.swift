import CADCore

protocol CertifiedIntersectionPlaneIntersecting: Sendable {
    func intersections(
        curve: CertifiedIntersectionCurve3D,
        planeSurface: Surface3D,
        reduction: CertifiedIntersectionPlaneReduction,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        sectionCurveIntersector: any CurveSurfaceIntersecting
    ) throws -> [CurveSurfaceIntersection]
}
