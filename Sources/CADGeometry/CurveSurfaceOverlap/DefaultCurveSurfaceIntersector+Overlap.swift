import CADCore

extension DefaultCurveSurfaceIntersector: CurveSurfaceIntersectionResolving {
    public func intersectionResult(
        curve: Curve3D,
        surface: Surface3D,
        options: CurveSurfaceIntersectionOptions = .init(),
        tolerance: ModelingTolerance
    ) throws -> CurveSurfaceIntersectionResult {
        try CurveSurfaceOverlapResolver().resolve(curve: curve, surface: surface, options: options,
                                                tolerance: tolerance, intersector: self)
    }
}
