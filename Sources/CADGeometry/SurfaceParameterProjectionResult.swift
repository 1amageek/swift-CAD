public enum SurfaceParameterProjectionResult: Hashable, Sendable {
    case projected(SurfaceParameterProjection)
    case outsideTolerance(residual: Double)
}
