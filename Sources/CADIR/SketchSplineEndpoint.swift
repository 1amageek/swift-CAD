public enum SketchSplineEndpoint: String, Sendable, Hashable {
    case start
    case end
}

#if !hasFeature(Embedded)
extension SketchSplineEndpoint: Codable {}
#endif
