public enum BRepRepairAction: String, Codable, Hashable, Sendable, CaseIterable {
    case deduplicateOwnershipReferences
    case reorderAndOrientLoopCoedges
    case pruneUnreferencedTopology

    var requiredValidationScopes: Set<TopologyValidationScope> {
        switch self {
        case .deduplicateOwnershipReferences, .pruneUnreferencedTopology:
            [.references]
        case .reorderAndOrientLoopCoedges:
            [.loops, .pcurves, .orientation]
        }
    }
}
