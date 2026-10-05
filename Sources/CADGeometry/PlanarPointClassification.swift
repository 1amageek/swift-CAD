public enum PlanarPointClassification: String, Equatable, Hashable, Sendable {
    case inside
    case boundary
    case outside
    case indeterminate
}

#if !hasFeature(Embedded)
extension PlanarPointClassification: Codable {}
#endif
