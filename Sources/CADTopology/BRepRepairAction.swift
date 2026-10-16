public enum BRepRepairAction: String, Hashable, Sendable, CaseIterable {
    case deduplicateOwnershipReferences
    case reorderAndOrientLoopCoedges
    case reconstructCurveRepresentations
    case sewWireVertices
    case removeDuplicateWireUses
    case collapseSmallWireEdges
    case restorePeriodicCharts
    case restoreSingularBoundaryUses
    case removeDuplicateFaces
    case sewShellEdges
    case orientShellFaces
    case orientSolidComponents
    case pruneUnreferencedTopology

    func requires(_ scope: TopologyValidationScope) -> Bool {
        switch self {
        case .deduplicateOwnershipReferences, .pruneUnreferencedTopology:
            scope == .references
        case .reconstructCurveRepresentations:
            scope == .references || scope == .pcurves
        case .sewWireVertices, .removeDuplicateWireUses, .collapseSmallWireEdges:
            scope == .references || scope == .loops
        case .restorePeriodicCharts:
            scope == .loops || scope == .pcurves
        case .restoreSingularBoundaryUses:
            scope == .references || scope == .loops || scope == .pcurves
        case .removeDuplicateFaces, .sewShellEdges:
            scope == .references || scope == .orientation || scope == .manifold || scope == .watertight
        case .orientShellFaces:
            scope == .orientation || scope == .manifold || scope == .watertight
        case .orientSolidComponents:
            scope == .references || scope == .orientation || scope == .manifold || scope == .watertight || scope == .volume
        case .reorderAndOrientLoopCoedges:
            scope == .loops || scope == .pcurves || scope == .orientation
        }
    }

    var requiredValidationScopes: Set<TopologyValidationScope> {
        switch self {
        case .deduplicateOwnershipReferences, .pruneUnreferencedTopology:
            [.references]
        case .reconstructCurveRepresentations:
            [.references, .pcurves]
        case .sewWireVertices, .removeDuplicateWireUses, .collapseSmallWireEdges:
            [.references, .loops]
        case .restorePeriodicCharts:
            [.loops, .pcurves]
        case .restoreSingularBoundaryUses:
            [.references, .loops, .pcurves]
        case .removeDuplicateFaces:
            [.references, .orientation, .manifold, .watertight]
        case .sewShellEdges:
            [.references, .orientation, .manifold, .watertight]
        case .orientShellFaces:
            [.orientation, .manifold, .watertight]
        case .orientSolidComponents:
            [.references, .orientation, .manifold, .watertight, .volume]
        case .reorderAndOrientLoopCoedges:
            [.loops, .pcurves, .orientation]
        }
    }
}

#if !hasFeature(Embedded)
extension BRepRepairAction: Codable {}
#endif
