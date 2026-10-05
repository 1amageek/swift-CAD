public enum CurveSurfaceIntersectionKind: String, Hashable, Sendable {
    case transverse
    case tangent
    case mixed
}

#if !hasFeature(Embedded)
extension CurveSurfaceIntersectionKind: Codable {}
#endif
