public enum CurveExtensionEnd: String, CaseIterable, Hashable, Sendable {
    case start
    case end
    case both
}

#if !hasFeature(Embedded)
extension CurveExtensionEnd: Codable {}
#endif
