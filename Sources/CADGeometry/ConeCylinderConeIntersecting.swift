import CADCore

protocol ConeCylinderConeIntersecting: Sendable {
    func supports(
        curve: CertifiedConeCylinderIntersectionCurve,
        coneSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Bool

    func intersections(
        curve: CertifiedConeCylinderIntersectionCurve,
        coneSurface: Surface3D,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CurveSurfaceIntersection]
}
