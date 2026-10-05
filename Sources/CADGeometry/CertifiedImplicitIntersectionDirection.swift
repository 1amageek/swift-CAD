public enum CertifiedImplicitIntersectionDirection: String, Sendable, Hashable {
    case forward
    case reversed
}

#if !hasFeature(Embedded)
extension CertifiedImplicitIntersectionDirection: Codable {}
#endif
