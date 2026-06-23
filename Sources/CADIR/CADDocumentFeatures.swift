import CADCore

public extension CADDocument {
    @discardableResult
    mutating func appendFeature(
        _ feature: FeatureNode,
        tolerance: ModelingTolerance = .standard
    ) throws -> FeatureID {
        var updatedDocument = self
        try updatedDocument.designGraph.appendFeature(feature, tolerance: tolerance)
        try updatedDocument.validate(tolerance: tolerance)
        self = updatedDocument
        return feature.id
    }
}

extension DesignGraph {
    @discardableResult
    mutating func appendFeature(
        _ feature: FeatureNode,
        tolerance: ModelingTolerance = .standard
    ) throws -> FeatureID {
        guard nodes[feature.id] == nil,
              order.contains(feature.id) == false else {
            throw FeatureEvaluationError.invalidGraph("Feature IDs must be unique.")
        }

        var updatedGraph = self
        updatedGraph.nodes[feature.id] = feature
        updatedGraph.order.append(feature.id)
        updatedGraph.dependencies.append(contentsOf: feature.inputDependencyEdges)
        updatedGraph.revision = updatedGraph.revision.advanced()
        try updatedGraph.validate(tolerance: tolerance)
        self = updatedGraph
        return feature.id
    }
}

extension FeatureNode {
    var inputDependencyEdges: [DependencyEdge] {
        Set(inputs.map(\.featureID))
            .sorted { $0.description < $1.description }
            .map { DependencyEdge(source: $0, target: id) }
    }
}
