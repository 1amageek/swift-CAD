import CADCore

protocol CurveSurfaceTangentIntersectionResolving: Sendable {
    func intersection(
        curve: Curve3D,
        surface: Surface3D,
        parameter: Double,
        options: CurveSurfaceIntersectionOptions,
        iterations: Int,
        tolerance: ModelingTolerance
    ) throws -> CurveSurfaceIntersection?
}
