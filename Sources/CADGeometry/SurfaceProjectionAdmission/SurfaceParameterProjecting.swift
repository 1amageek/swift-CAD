import CADCore

/// Whole original finite-support closest-point query with caller-owned admission.
public protocol SurfaceParameterProjecting: Sendable {
    func projection(of point:Point3D,on surface:Surface3D,over domain:SurfaceParameterBox,
        options:SurfaceParameterProjectionOptions,tolerance:ModelingTolerance,
        maximumSubdivisionDepth:Int,consumeWork:@escaping @Sendable(Int)throws->Void) throws -> SurfaceParameterProjection
    func projectionResult(of point:Point3D,on surface:Surface3D,over domain:SurfaceParameterBox,
        options:SurfaceParameterProjectionOptions,tolerance:ModelingTolerance,
        maximumSubdivisionDepth:Int,consumeWork:@escaping @Sendable(Int)throws->Void) throws -> SurfaceParameterProjectionResult
}
