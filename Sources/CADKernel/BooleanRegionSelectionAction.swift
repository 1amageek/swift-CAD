public enum BooleanRegionSelectionAction: String, Codable, Hashable, Sendable {
    case keep
    case keepReversed
    case discard
    case partitionBoundary
}
