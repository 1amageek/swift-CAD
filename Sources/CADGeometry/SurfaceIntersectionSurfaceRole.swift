public enum SurfaceIntersectionSurfaceRole: String, Hashable, Sendable {
    case first
    case second
}

#if !hasFeature(Embedded)
extension SurfaceIntersectionSurfaceRole: Codable {}
#endif
