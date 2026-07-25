import CADCore

protocol ParallelTorusTorusPlaneIntersecting: Sendable {
    func intersections(
        curve: CertifiedParallelTorusTorusIntersectionCurve,
        planeSurface: Surface3D,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CurveSurfaceIntersection]
}
