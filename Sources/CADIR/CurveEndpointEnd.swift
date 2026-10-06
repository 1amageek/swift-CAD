public enum CurveEndpointEnd: String, CaseIterable, Hashable, Sendable {
    case start
    case end
}

#if !hasFeature(Embedded)
extension CurveEndpointEnd: Codable {}
#endif
