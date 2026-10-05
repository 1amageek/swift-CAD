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

    public func intersectionResult(curve: Curve3D, surface: Surface3D,
        options: CurveSurfaceIntersectionOptions = .init(), tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil,
        maximumAlgebraicDepth: Int? = nil) throws -> CurveSurfaceIntersectionResult {
        let invocation = try CurveSurfaceQueryInvocation(
            maximumSubdivisionDepth: min(options.maximumSubdivisionDepth, maximumSubdivisionDepth),
            maximumSpanCount: maximumSpanCount, remainingSourceDepth: remainingSourceDepth,
            consumeWork: consumeWork, consumeStorage: consumeStorage,
            maximumAlgebraicDepth: maximumAlgebraicDepth)
        return try CurveSurfaceOverlapResolver().resolve(curve: curve, surface: surface,
            options: options, tolerance: tolerance, intersector: self, invocation: invocation)
    }

}
