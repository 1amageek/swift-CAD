public enum SurfaceNormalAlignment: String, CaseIterable, Hashable, Sendable {
    case aligned
    case opposed
}

#if !hasFeature(Embedded)
extension SurfaceNormalAlignment: Codable {}
#endif
