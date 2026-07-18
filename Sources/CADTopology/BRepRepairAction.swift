public enum BRepRepairAction: String, Codable, Hashable, Sendable, CaseIterable {
    case deduplicateOwnershipReferences
    case reorderAndOrientLoopCoedges
    case pruneUnreferencedTopology
}
