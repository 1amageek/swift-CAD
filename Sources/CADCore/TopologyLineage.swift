public struct TopologyLineage: Equatable, Sendable {
    public let output: SubshapeID
    public let parents: [SubshapeID]
    public let relation: TopologyLineageRelation

    public init(
        output: SubshapeID,
        parents: [SubshapeID] = [],
        relation: TopologyLineageRelation
    ) {
        self.output = output
        self.parents = Array(Set(parents)).sorted()
        self.relation = relation
    }

    /// Retains an already canonical parent array without repeating its construction.
    package init?(
        output: SubshapeID,
        canonicalParents: [SubshapeID],
        relation: TopologyLineageRelation
    ) {
        self.output = output
        self.parents = canonicalParents
        self.relation = relation
        guard isStructurallyValid else { return nil }
    }

    public var isStructurallyValid: Bool {
        guard output.isValid, hasValidParentCardinality else { return false }
        var previous: SubshapeID?
        for parent in parents {
            guard parent.isValid, parent != output else { return false }
            if let previous, !(previous < parent) { return false }
            previous = parent
        }
        return true
    }

    private var hasValidParentCardinality: Bool {
        switch relation {
        case .generated:
            return parents.isEmpty
        case .preserved, .split:
            return parents.count == 1
        case .merged:
            return parents.count > 1
        }
    }
}

#if !hasFeature(Embedded)
extension TopologyLineage: Codable {}
#endif
