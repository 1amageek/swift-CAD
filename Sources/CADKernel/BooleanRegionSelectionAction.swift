public enum BooleanRegionSelectionAction: String, Hashable, Sendable {
    case keep
    case keepReversed
    case discard
    case partitionBoundary
}

#if !hasFeature(Embedded)
extension BooleanRegionSelectionAction: Codable {}
#endif
