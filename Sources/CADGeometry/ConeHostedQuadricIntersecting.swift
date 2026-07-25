import CADCore

protocol ConeHostedQuadricIntersecting: Sendable {
    func supports(
        curve: CertifiedIntersectionCurve3D,
        targetSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Bool

    func intersections(
        curve: CertifiedIntersectionCurve3D,
        targetSurface: Surface3D,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CurveSurfaceIntersection]
}
