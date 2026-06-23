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

    @discardableResult
    mutating func replaceFeature(
        _ feature: FeatureNode,
        tolerance: ModelingTolerance = .standard
    ) throws -> FeatureID {
        let featureIDs = try replaceFeatures([feature], tolerance: tolerance)
        guard let featureID = featureIDs.first else {
            throw FeatureEvaluationError.invalidGraph("Feature replacement did not return a feature ID.")
        }
        return featureID
    }

    @discardableResult
    mutating func replaceFeatures(
        _ features: [FeatureNode],
        tolerance: ModelingTolerance = .standard
    ) throws -> [FeatureID] {
        var updatedDocument = self
        let featureIDs = try updatedDocument.designGraph.replaceFeatures(features, tolerance: tolerance)
        try updatedDocument.validate(tolerance: tolerance)
        self = updatedDocument
        return featureIDs
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

    @discardableResult
    mutating func replaceFeatures(
        _ features: [FeatureNode],
        tolerance: ModelingTolerance = .standard
    ) throws -> [FeatureID] {
        guard features.isEmpty == false else {
            return []
        }
        let featureIDs = features.map(\.id)
        guard Set(featureIDs).count == featureIDs.count else {
            throw FeatureEvaluationError.invalidGraph("Replacement feature IDs must be unique.")
        }
        for featureID in featureIDs {
            guard nodes[featureID] != nil,
                  order.contains(featureID) else {
                throw FeatureEvaluationError.invalidGraph("Replacement features must already exist.")
            }
        }

        let replacementIDs = Set(featureIDs)
        var updatedGraph = self
        for feature in features {
            updatedGraph.nodes[feature.id] = feature
        }
        updatedGraph.dependencies.removeAll { dependency in
            replacementIDs.contains(dependency.target)
        }
        updatedGraph.dependencies.append(contentsOf: features.replacementDependencyEdges)
        updatedGraph.revision = updatedGraph.revision.advanced()
        try updatedGraph.validate(tolerance: tolerance)
        self = updatedGraph
        return featureIDs
    }
}

extension FeatureNode {
    var inputDependencyEdges: [DependencyEdge] {
        Set(inputs.map(\.featureID))
            .sorted { $0.description < $1.description }
            .map { DependencyEdge(source: $0, target: id) }
    }
}

private extension Array where Element == FeatureNode {
    var replacementDependencyEdges: [DependencyEdge] {
        sorted { $0.id.description < $1.id.description }
            .flatMap(\.inputDependencyEdges)
    }
}
