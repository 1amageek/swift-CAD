import CADCore

public protocol BoundedSurfaceSurfaceIntersecting: Sendable {
    func intersections(
        first: Surface3D,
        second: Surface3D,
        boundaryPoints: [Point3D],
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection]?
}
