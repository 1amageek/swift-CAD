import CADCore

extension DefaultSurfaceSurfaceIntersector {
    public func intersectionResult(first: Surface3D, second: Surface3D,
        options: SurfaceSurfaceIntersectionOptions = .init(), tolerance: ModelingTolerance) throws -> SurfaceSurfaceIntersectionResult {
        if let native = try NativeSurfaceSurfacePointProducer().resolve(first: first, second: second,
            options: options, tolerance: tolerance) { return native }
        let intersections = try intersections(first: first, second: second, options: options, tolerance: tolerance)
        try CurrentTaskCancellationChecker().checkCancellation()
        return .init(intersections: intersections)
    }

    public func intersectionResult(first: Surface3D, second: Surface3D,
        options: SurfaceSurfaceIntersectionOptions = .init(), tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable () throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil,
        maximumAlgebraicDepth: Int? = nil) throws -> SurfaceSurfaceIntersectionResult {
        try options.validate(tolerance: tolerance)
        let admission = try SurfaceSurfaceQueryAdmission(maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
        if let native = try NativeSurfaceSurfacePointProducer().resolve(first: first, second: second,
            options: options, tolerance: tolerance, admission: admission) { return native }
        let intersections = try intersections(first: first, second: second, options: options, tolerance: tolerance,
            maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
            maximumAlgebraicDepth: maximumAlgebraicDepth)
        try admission.reserve(count: 1, stride: MemoryLayout<SurfaceSurfaceIntersectionResult>.stride)
        try CurrentTaskCancellationChecker().checkCancellation()
        return .init(intersections: intersections)
    }

    public func intersectionResult(first: Surface3D, over firstBox: SurfaceParameterBox,
        second: Surface3D, over secondBox: SurfaceParameterBox,
        options: SurfaceSurfaceIntersectionOptions = .init(), tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable () throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil,
        maximumAlgebraicDepth: Int? = nil) throws -> SurfaceSurfaceIntersectionResult {
        try options.validate(tolerance: tolerance)
        let admission = try SurfaceSurfaceQueryAdmission(maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
        if let native = try NativeSurfaceSurfacePointProducer().resolve(first: first, second: second,
            firstBox: firstBox, secondBox: secondBox, options: options,
            tolerance: tolerance, admission: admission) { return native }
        let intersections = try intersections(first: first, over: firstBox, second: second, over: secondBox,
            options: options, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
        try admission.reserve(count: 1, stride: MemoryLayout<SurfaceSurfaceIntersectionResult>.stride)
        try CurrentTaskCancellationChecker().checkCancellation()
        return .init(intersections: intersections)
    }
}
