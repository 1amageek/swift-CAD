import CADCore
import CADIR
import CADTopology

struct SubshapeIndexBuilder {
    func build(
        candidates: [SubshapeID: TopologyReference],
        lineage: [SubshapeID: TopologyLineage],
        model: BRepModel
    ) throws -> SubshapeIndex {
        let candidatesByReference = Dictionary(grouping: candidates.keys) { subshapeID in
            candidates[subshapeID]
        }
        var entries: [SubshapeID: TopologyReference] = [:]
        for reference in candidatesByReference.keys.compactMap({ $0 }).sorted(by: isOrderedBefore) {
            let identityCandidates = candidatesByReference[reference, default: []].sorted()
            let subshapeID = try canonicalCandidate(in: identityCandidates, lineage: lineage)
            entries[subshapeID] = reference
        }
        let index = SubshapeIndex(entries)
        try index.validate(against: model, lineage: lineage)
        return index
    }

    private func canonicalCandidate(
        in candidates: [SubshapeID],
        lineage: [SubshapeID: TopologyLineage]
    ) throws -> SubshapeID {
        guard let first = candidates.first else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: nil,
                message: "Live topology has no subshape identity candidate."
            )
        }
        guard candidates.count > 1 else { return first }

        let candidateSet = Set(candidates)
        let descendants = candidates.filter { candidate in
            let ancestors = ancestorIDs(of: candidate, lineage: lineage)
            return candidateSet.subtracting([candidate]).isSubset(of: ancestors)
        }
        guard descendants.count == 1, let descendant = descendants.first else {
            throw KernelError(
                phase: .topology,
                code: .ambiguousSelection,
                featureID: first.featureID,
                subshapeID: first,
                tolerance: nil,
                message: "Live topology has multiple identities without one unique lineage descendant."
            )
        }
        return descendant
    }

    private func ancestorIDs(
        of subshapeID: SubshapeID,
        lineage: [SubshapeID: TopologyLineage]
    ) -> Set<SubshapeID> {
        var ancestors = Set<SubshapeID>()
        var pending = lineage[subshapeID]?.parents ?? []
        while let parent = pending.popLast() {
            guard ancestors.insert(parent).inserted else { continue }
            pending.append(contentsOf: lineage[parent]?.parents ?? [])
        }
        return ancestors
    }

    private func isOrderedBefore(
        _ lhs: TopologyReference,
        _ rhs: TopologyReference
    ) -> Bool {
        topologyKey(lhs) < topologyKey(rhs)
    }

    private func topologyKey(_ reference: TopologyReference) -> String {
        switch reference {
        case let .body(id): "0:\(id.rawValue.uuidString)"
        case let .face(id): "1:\(id.rawValue.uuidString)"
        case let .edge(id): "2:\(id.rawValue.uuidString)"
        case let .vertex(id): "3:\(id.rawValue.uuidString)"
        }
    }

}
