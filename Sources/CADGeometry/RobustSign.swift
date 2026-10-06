public enum RobustSign: String, Hashable, Sendable, CaseIterable {
    case negative
    case zero
    case positive
    case indeterminate
}

#if !hasFeature(Embedded)
extension RobustSign: Codable {}
#endif
