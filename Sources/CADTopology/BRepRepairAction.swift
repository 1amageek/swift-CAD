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
