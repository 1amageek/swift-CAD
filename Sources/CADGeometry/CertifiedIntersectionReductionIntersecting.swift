import CADCore

protocol CertifiedIntersectionReductionIntersecting: Sendable {
    func intersections(
        curve: CertifiedIntersectionCurve3D,
        targetSurface: Surface3D,
        reduction: CertifiedIntersectionReduction,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        sectionCurveIntersector: any CurveSurfaceIntersecting
    ) throws -> [CurveSurfaceIntersection]
}
