import CADCore

public struct DefaultBoundedSurfaceSurfaceIntersector: BoundedSurfaceSurfaceIntersecting {
    public init() {}

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
