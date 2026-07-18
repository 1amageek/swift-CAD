public enum SurfaceSurfaceIntersection: Codable, Hashable, Sendable {
    case curve(SurfaceSurfaceIntersectionCurve)
    case point(SurfaceSurfaceIntersectionPoint)
    case coincident(SurfaceSurfaceCoincidence)
}
