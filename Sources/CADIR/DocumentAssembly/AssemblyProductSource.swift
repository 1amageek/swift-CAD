/// Exact PRODUCT_DEFINITION_FORMATION_WITH_SPECIFIED_SOURCE literals.
public enum AssemblyProductSource: String, Equatable, Sendable {
    case made
    case bought
    case notKnown = "not_known"
}

#if !hasFeature(Embedded)
extension AssemblyProductSource: Codable {}
#endif
