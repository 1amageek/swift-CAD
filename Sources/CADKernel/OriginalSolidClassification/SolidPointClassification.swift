public enum SolidPointClassification: String, Hashable, Sendable {
    case inside
    case boundary
    case outside
}

#if !hasFeature(Embedded)
extension SolidPointClassification: Codable {}
#endif
