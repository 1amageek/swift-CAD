public struct TopologyLineage: Codable, Equatable, Sendable {
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

    public var isStructurallyValid: Bool {
        output.isValid
            && parents.allSatisfy(\.isValid)
            && !parents.contains(output)
            && parents == Array(Set(parents)).sorted()
            && hasValidParentCardinality
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
