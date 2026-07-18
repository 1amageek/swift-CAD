import CADCore

public protocol SurfaceSurfaceIntersecting: Sendable {
    func intersections(
        first: Surface3D,
        second: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection]
}
