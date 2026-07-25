import CADCore

protocol ConeCylinderSphereIntersecting: Sendable {
    func intersections(
        curve: CertifiedConeCylinderIntersectionCurve,
        sphereSurface: Surface3D,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CurveSurfaceIntersection]
}
