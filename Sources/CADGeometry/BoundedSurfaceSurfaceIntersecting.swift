import CADCore

public protocol BoundedSurfaceSurfaceIntersecting: Sendable {
    func intersections(
        first: Surface3D,
        second: Surface3D,
        boundaryPoints: [Point3D],
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection]?
    func intersections(
        first: Surface3D,
        second: Surface3D,
        boundaryPoints: [Point3D],
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        maximumSpanCount: Int,
        maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable () throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?
    ) throws -> [SurfaceSurfaceIntersection]?
}

public extension BoundedSurfaceSurfaceIntersecting {
    // FIXME(INCOMPLETE_IMPLEMENTATION): An injected surface-pair conformer
    // must forward every original work/storage visit before bounded callers can
    // consume its results. The legacy requirement cannot supply that witness.
    func intersections(first: Surface3D, second: Surface3D, boundaryPoints: [Point3D],
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable () throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> [SurfaceSurfaceIntersection]? {
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "This surface-pair conformer has no caller-admitted original producer.")
    }
}
