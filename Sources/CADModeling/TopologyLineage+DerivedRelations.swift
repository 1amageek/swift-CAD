import CADCore

extension Dictionary where Key == SubshapeID, Value == TopologyLineage {
    /// The same lineage with each relation derived from its parents: none generated, several
    /// merged, one parent shared by several outputs split, otherwise preserved. A stage that
    /// rewrites parents (tracing them through a temporary stage or dropping unpublished ones)
    /// applies this so the relations still describe the parents they name.
    package func withRelationsDerivedFromParents() -> [SubshapeID: TopologyLineage] {
        var parentUseCount: [SubshapeID: Int] = [:]
        for entry in values {
            for parent in entry.parents {
                parentUseCount[parent, default: 0] += 1
            }
        }
        return mapValues { entry in
            let relation: TopologyLineageRelation
            if entry.parents.isEmpty {
                relation = .generated
            } else if entry.parents.count > 1 {
                relation = .merged
            } else if parentUseCount[entry.parents[0], default: 0] > 1 {
                relation = .split
            } else {
                relation = .preserved
            }
            return TopologyLineage(output: entry.output, parents: entry.parents, relation: relation)
        }
    }
}
