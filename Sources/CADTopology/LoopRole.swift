/// The containment role of a face-local trimming loop.
public enum LoopRole: String, Equatable, Sendable {
    case outer
    case inner
}

#if !hasFeature(Embedded)
extension LoopRole: Codable {}
#endif
