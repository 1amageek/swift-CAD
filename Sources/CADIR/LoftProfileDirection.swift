/// Traversal policy for Loft correspondence without changing the source region.
public enum LoftProfileDirection: String, Hashable, Sendable {
    case automatic
    case forward
    case reversed
}

#if !hasFeature(Embedded)
extension LoftProfileDirection: Codable {}
#endif
