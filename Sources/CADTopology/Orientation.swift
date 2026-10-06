/// The traversal direction of a topological entity relative to its canonical geometry.
public enum Orientation: String, Equatable, Sendable {
    case forward
    case reversed
}

#if !hasFeature(Embedded)
extension Orientation: Codable {}
#endif
