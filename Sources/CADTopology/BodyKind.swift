/// The closure contract of a topological body.
public enum BodyKind: String, Equatable, Sendable {
    case solid
    case sheet
}

#if !hasFeature(Embedded)
extension BodyKind: Codable {}
#endif
