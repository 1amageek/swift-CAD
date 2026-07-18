public enum ProjectionQueryResult: Sendable {
    case curveClosest(CurveProjectionResult)
    case curveDirectional(CurveDirectionalProjectionResult)
    case edgeClosest(EdgeProjectionResult)
    case edgeDirectional(EdgeDirectionalProjectionResult)
    case surfaceClosest(SurfaceProjectionResult)
    case surfaceDirectional(SurfaceDirectionalProjectionResult)
}
