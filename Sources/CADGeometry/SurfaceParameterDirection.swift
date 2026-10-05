public enum SurfaceParameterDirection: String, Hashable, Sendable {
    case u
    case v
}

#if !hasFeature(Embedded)
extension SurfaceParameterDirection: Codable {}
#endif
