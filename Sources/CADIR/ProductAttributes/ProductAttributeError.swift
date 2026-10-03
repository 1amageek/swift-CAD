public enum ProductAttributeError: Error, Equatable, Sendable {
    case invalidSource(String)
    case missingTarget(String)
    case ambiguousProperty(String)
    case inconsistentArtifact(String)
    case unsupportedSemantics(String)
    case resourceLimitExceeded(String)
}
