import CADCore

public struct DefaultBoundedSurfaceSurfaceIntersector: BoundedSurfaceSurfaceIntersecting {
    public init() {}

    // FIXME(INCOMPLETE_IMPLEMENTATION): This caller-admitted production route
    // currently uses the finite regular original parametric producer. Admitted
    // specialized unbounded analytic/plane-cone and critical/coincident contacts
    // still require their complete same-ledger proof before full domain closure.
    public func intersections(first: Surface3D, second: Surface3D, boundaryPoints: [Point3D],
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable () throws -> Void,
        consumeStorage: @escaping @Sendable (Int) throws -> Void) throws -> [SurfaceSurfaceIntersection]? {
        try options.validate(tolerance: tolerance)
        for point in boundaryPoints { try consumeWork(); try point.validate() }
        return try DefaultSurfaceSurfaceIntersector().intersections(first: first, second: second,
            options: options, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            consumeWork: consumeWork, consumeStorage: consumeStorage)
    }

    public func intersections(
        first: Surface3D,
        second: Surface3D,
        boundaryPoints: [Point3D],
        options: SurfaceSurfaceIntersectionOptions = .init(),
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection]? {
        try options.validate(tolerance: tolerance)
        try first.validate(tolerance: tolerance)
        try second.validate(tolerance: tolerance)

        switch (CanonicalAnalyticSurface(first), CanonicalAnalyticSurface(second)) {
        case let (.plane(plane), .cone(cone)):
            return try BoundedPlaneConeSurfaceIntersector().intersections(
                plane: plane,
                cone: cone,
                firstSurface: first,
                secondSurface: second,
                boundaryPoints: boundaryPoints,
                options: options,
                tolerance: tolerance
            )
        case let (.cone(cone), .plane(plane)):
            return try BoundedPlaneConeSurfaceIntersector().intersections(
                plane: plane,
                cone: cone,
                firstSurface: first,
                secondSurface: second,
                boundaryPoints: boundaryPoints,
                options: options,
                tolerance: tolerance
            )
        default:
            return nil
        }
    }
}
