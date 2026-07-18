import CADCore
import CADIR
import CADTopology

struct EdgeOffsetEvaluationChange {
    var subshapes: [SubshapeID: TopologyReference]
    var removedSubshapeIDs: Set<SubshapeID>
    var lineage: [SubshapeID: TopologyLineage]

    mutating func merge(_ other: EdgeOffsetEvaluationChange) throws {
        for (subshapeID, reference) in other.subshapes {
            if let current = subshapes[subshapeID], current != reference {
                throw FeatureEvaluationError.invalidGraph(
                    "Symmetric edge offset produced conflicting subshape identities."
                )
            }
            subshapes[subshapeID] = reference
        }
        for (subshapeID, entry) in other.lineage {
            if let current = lineage[subshapeID], current != entry {
                throw FeatureEvaluationError.invalidGraph(
                    "Symmetric edge offset produced conflicting topology lineage."
                )
            }
            lineage[subshapeID] = entry
        }
        removedSubshapeIDs.formUnion(other.removedSubshapeIDs)
    }
}
