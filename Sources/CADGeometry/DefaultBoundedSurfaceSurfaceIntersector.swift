import CADCore

public struct DefaultBoundedSurfaceSurfaceIntersector: BoundedSurfaceSurfaceIntersecting {
    public init() {}

    public func intersections(first: Surface3D, second: Surface3D, boundaryPoints: [Point3D],
        options: SurfaceSurfaceIntersectionOptions = .init(), tolerance: ModelingTolerance) throws -> [SurfaceSurfaceIntersection]? {
        try options.validate(tolerance: tolerance)
        var execution = try OriginalQueryExecution.surfaceSurface(options: options,
            context: .init(operation: .surfaceSurface, entry: .ordinary, stage: .request,
                first: .init(role: .firstSurface, request: .wholeSourceSupport),
                second: .init(role: .secondSurface, request: .wholeSourceSupport)))
        return try intersections(first: first, second: second, boundaryPoints: boundaryPoints,
            options: options, tolerance: tolerance, using: &execution)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Bounded public callers use the original
    // whole-support producers here. Boundary samples do not specify selected UV
    // domains; unbounded analytic and unresolved critical/coincident coverage
    // still require original domain authority before complete publication.
    public func intersections(first: Surface3D, second: Surface3D, boundaryPoints: [Point3D],
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> [SurfaceSurfaceIntersection]? {
        execution.context = execution.context.fillingMissing(from: .init(operation: .surfaceSurface,
            entry: .admitted, stage: .request,
            first: .init(role: .firstSurface, request: .wholeSourceSupport),
            second: .init(role: .secondSurface, request: .wholeSourceSupport)))
        do {
            try execution.checkpoint()
            try options.validate(tolerance: tolerance)
            for point in boundaryPoints {
                try execution.consumeWork(1)
                try point.validate()
            }
            let result = try DefaultSurfaceSurfaceIntersector().intersections(first: first, second: second,
                options: options, tolerance: tolerance, using: &execution)
            execution.context = execution.context.at(stage: .publication)
            try execution.checkpoint()
            return result
        } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance) }
    }

}
