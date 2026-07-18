import CADCore

public protocol CurveSurfaceIntersecting: Sendable {
    func intersections(
        curve: Curve3D,
        surface: Surface3D,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CurveSurfaceIntersection]
}
