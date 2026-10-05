import CADCore

public struct DefaultSurfaceParameterProjector: SurfaceParameterProjecting {
    public init() {}
    public func projection(of point:Point3D,on surface:Surface3D,over domain:SurfaceParameterBox,
        options:SurfaceParameterProjectionOptions,tolerance:ModelingTolerance,
        maximumSubdivisionDepth:Int,consumeWork:@escaping @Sendable(Int)throws->Void) throws -> SurfaceParameterProjection {
        try options.validate(tolerance:tolerance)
        let invocation = try CurveSurfaceQueryInvocation(maximumSubdivisionDepth:maximumSubdivisionDepth,
            maximumSpanCount:min(262_144,options.maximumSubdivisionCells),remainingSourceDepth:maximumSubdivisionDepth,
            consumeWork:consumeWork)
        try invocation.consumeFixedWork()
        let prepared = try PreparedSurfaceDifferentialEncloser(surface:surface,tolerance:tolerance,
            remainingSourceDepth:maximumSubdivisionDepth,maximumSubdivisionDepth:maximumSubdivisionDepth,
            consumeWork:invocation.consumeFixedWork)
        try domain.validateAssumingSurfaceValidated(for:surface,tolerance:tolerance)
        var limits = options
        limits.maximumSubdivisionDepth = min(options.maximumSubdivisionDepth,maximumSubdivisionDepth)
        return try ProceduralSurfaceParameterProjector(invocation:invocation,originalDomain:domain,
            originalPreparation:prepared).closestProjection(of:point,on:surface,options:limits,tolerance:tolerance)
    }
    public func projectionResult(of point:Point3D,on surface:Surface3D,over domain:SurfaceParameterBox,
        options:SurfaceParameterProjectionOptions,tolerance:ModelingTolerance,
        maximumSubdivisionDepth:Int,consumeWork:@escaping @Sendable(Int)throws->Void) throws -> SurfaceParameterProjectionResult {
        try options.validate(tolerance:tolerance); try point.validate()
        let invocation = try CurveSurfaceQueryInvocation(maximumSubdivisionDepth:maximumSubdivisionDepth,
            maximumSpanCount:min(262_144,options.maximumSubdivisionCells),remainingSourceDepth:maximumSubdivisionDepth,
            consumeWork:consumeWork)
        try invocation.consumeFixedWork()
        let prepared = try PreparedSurfaceDifferentialEncloser(surface:surface,tolerance:tolerance,
            remainingSourceDepth:maximumSubdivisionDepth,maximumSubdivisionDepth:maximumSubdivisionDepth,
            consumeWork:invocation.consumeFixedWork)
        try domain.validateAssumingSurfaceValidated(for:surface,tolerance:tolerance)
        var limits = options
        limits.maximumSubdivisionDepth = min(options.maximumSubdivisionDepth,maximumSubdivisionDepth)
        return try ProceduralSurfaceParameterProjector(invocation:invocation,originalDomain:domain,
            originalPreparation:prepared).boundedProjectionResult(of:point,on:surface,
            uBounds:domain.u.lower...domain.u.upper,vBounds:domain.v.lower...domain.v.upper,
            options:limits,tolerance:tolerance)
    }
}
