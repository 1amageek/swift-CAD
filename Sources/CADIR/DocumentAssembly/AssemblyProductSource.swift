/// Exact PRODUCT_DEFINITION_FORMATION_WITH_SPECIFIED_SOURCE literals.
public enum AssemblyProductSource: String, Codable, Equatable, Sendable {
    case made
    case bought
    case notKnown = "not_known"
}
