public enum TopologyLineageRelation: String, Hashable, Sendable, CaseIterable {
    case preserved
    case generated
    case split
    case merged
}

#if !hasFeature(Embedded)
extension TopologyLineageRelation: Codable {}
#endif
