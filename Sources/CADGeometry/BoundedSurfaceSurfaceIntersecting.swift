import CADCore

public protocol BoundedSurfaceSurfaceIntersecting: Sendable {
    func intersections(first: Surface3D, second: Surface3D, boundaryPoints: [Point3D],
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance) throws -> [SurfaceSurfaceIntersection]?

    func intersections(first: Surface3D, second: Surface3D, boundaryPoints: [Point3D],
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> [SurfaceSurfaceIntersection]?
}

public extension BoundedSurfaceSurfaceIntersecting {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Injected bounded producers must supply
    // complete original domain coverage through this direct requirement before
    // admitted callers may publish their results. An ordinary-only conformer
    // cannot establish the original source and caller admission witness.
    func intersections(first: Surface3D, second: Surface3D, boundaryPoints: [Point3D],
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> [SurfaceSurfaceIntersection]? {
        try execution.checkpoint()
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "This bounded producer has no direct original source witness.")
    }
}
