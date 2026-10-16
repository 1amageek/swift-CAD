import CADCore

protocol ConeHostedQuadricIntersecting: Sendable {
    func supports(
        curve: CertifiedIntersectionCurve3D,
        targetSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Bool

    func supports(
        curve: CertifiedIntersectionCurve3D,
        targetSurface: Surface3D,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> Bool

    func intersections(
        curve: CertifiedIntersectionCurve3D,
        targetSurface: Surface3D,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CurveSurfaceIntersection]

    func intersections(
        curve: CertifiedIntersectionCurve3D,
        targetSurface: Surface3D,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> [CurveSurfaceIntersection]
}
