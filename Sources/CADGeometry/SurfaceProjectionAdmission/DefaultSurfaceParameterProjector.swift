import CADCore

public struct DefaultSurfaceParameterProjector: SurfaceParameterProjecting {
    public init() {}
    public func projection(of point:Point3D,on surface:Surface3D,over domain:SurfaceParameterBox,
        options:SurfaceParameterProjectionOptions,tolerance:ModelingTolerance,
        maximumSubdivisionDepth:Int, remainingSourceDepth:Int = 16, maximumAlgebraicDepth:Int = 32, using execution:inout OriginalQueryExecution) throws -> SurfaceParameterProjection {
        try options.validate(tolerance:tolerance)
        try execution.consumeWork(1)
        let prepared = try PreparedSurfaceDifferentialEncloser(surface:surface,tolerance:tolerance,
            remainingSourceDepth:min(remainingSourceDepth, execution.effectiveLimits.remainingSourceDepth),
            maximumSubdivisionDepth:min(maximumSubdivisionDepth, execution.effectiveLimits.maximumSubdivisionDepth),
            maximumAlgebraicDepth:min(maximumAlgebraicDepth, execution.effectiveLimits.maximumValueDepth, execution.effectiveLimits.maximumCoefficientDepth), using:&execution)
        try domain.validateAssumingSurfaceValidated(for:surface,tolerance:tolerance)
        var limits = options
        limits.maximumSubdivisionDepth = min(options.maximumSubdivisionDepth,maximumSubdivisionDepth)
        return try ProceduralSurfaceParameterProjector(originalDomain:domain,
            originalPreparation:prepared,originalProof:true,
            maximumSpanCount:min(262_144,options.maximumSubdivisionCells,execution.effectiveLimits.maximumSpans),
            maximumSubdivisionDepth:min(maximumSubdivisionDepth, execution.effectiveLimits.maximumSubdivisionDepth),
            remainingSourceDepth:min(remainingSourceDepth, execution.effectiveLimits.remainingSourceDepth)).closestProjection(of:point,on:surface,options:limits,tolerance:tolerance,using:&execution)
    }
    public func projectionResult(of point:Point3D,on surface:Surface3D,over domain:SurfaceParameterBox,
        options:SurfaceParameterProjectionOptions,tolerance:ModelingTolerance,
        maximumSubdivisionDepth:Int, remainingSourceDepth:Int = 16, maximumAlgebraicDepth:Int = 32, using execution:inout OriginalQueryExecution) throws -> SurfaceParameterProjectionResult {
        try options.validate(tolerance:tolerance); try point.validate()
        try execution.consumeWork(1)
        let prepared = try PreparedSurfaceDifferentialEncloser(surface:surface,tolerance:tolerance,
            remainingSourceDepth:min(remainingSourceDepth, execution.effectiveLimits.remainingSourceDepth),
            maximumSubdivisionDepth:min(maximumSubdivisionDepth, execution.effectiveLimits.maximumSubdivisionDepth),
            maximumAlgebraicDepth:min(maximumAlgebraicDepth, execution.effectiveLimits.maximumValueDepth, execution.effectiveLimits.maximumCoefficientDepth), using:&execution)
        try domain.validateAssumingSurfaceValidated(for:surface,tolerance:tolerance)
        var limits = options
        limits.maximumSubdivisionDepth = min(options.maximumSubdivisionDepth,maximumSubdivisionDepth)
        return try ProceduralSurfaceParameterProjector(originalDomain:domain,
            originalPreparation:prepared,originalProof:true,
            maximumSpanCount:min(262_144,options.maximumSubdivisionCells,execution.effectiveLimits.maximumSpans),
            maximumSubdivisionDepth:min(maximumSubdivisionDepth, execution.effectiveLimits.maximumSubdivisionDepth),
            remainingSourceDepth:min(remainingSourceDepth, execution.effectiveLimits.remainingSourceDepth)).boundedProjectionResult(of:point,on:surface,
            uBounds:domain.u.lower...domain.u.upper,vBounds:domain.v.lower...domain.v.upper,
            options:limits,tolerance:tolerance,using:&execution)
    }
}
