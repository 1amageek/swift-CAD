import CADCore
@testable import CADGeometry
struct CurveSurfaceOverlapResolver {
    enum Failure: Error { case unselectedLegacyRoute }
    func resolve(curve:Curve3D,surface:Surface3D,options:CurveSurfaceIntersectionOptions,
        tolerance:ModelingTolerance,intersector:DefaultCurveSurfaceIntersector,
        invocation:CurveSurfaceQueryInvocation? = nil) throws -> CurveSurfaceIntersectionResult {
        throw Failure.unselectedLegacyRoute
    }
}
