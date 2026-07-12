public enum TopologyLineageRelation: String, Codable, Hashable, Sendable, CaseIterable {
    case preserved
    case generated
    case split
    case merged
}
