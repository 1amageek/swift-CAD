import CADCore

public extension CADDocument {
    @discardableResult
    mutating func appendFeature(
        _ feature: FeatureNode,
        tolerance: ModelingTolerance = .standard
    ) throws -> FeatureID {
        var updatedDocument = self
        try updatedDocument.designGraph.appendFeature(
            feature,
            tolerance: tolerance,
            validatesGraph: false
        )
        try updatedDocument.validate(tolerance: tolerance)
        self = updatedDocument
        return feature.id
    }

    @discardableResult
    mutating func replaceFeature(
        _ feature: FeatureNode,
        tolerance: ModelingTolerance = .standard
    ) throws -> FeatureID {
        var updatedDocument = self
        try updatedDocument.designGraph.replaceFeature(
            feature,
            tolerance: tolerance,
            validatesGraph: false
        )
        try updatedDocument.validate(tolerance: tolerance)
        self = updatedDocument
        return feature.id
    }

    @discardableResult
    mutating func replaceFeatures(
        _ features: [FeatureNode],
        tolerance: ModelingTolerance = .standard
    ) throws -> [FeatureID] {
        var updatedDocument = self
        let featureIDs = try updatedDocument.designGraph.replaceFeatures(
            features,
            tolerance: tolerance,
            validatesGraph: false
        )
        try updatedDocument.validate(tolerance: tolerance)
        self = updatedDocument
        return featureIDs
    }
}

extension DesignGraph {
    @discardableResult
    mutating func appendFeature(
        _ feature: FeatureNode,
        tolerance: ModelingTolerance = .standard,
        validatesGraph: Bool = true
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
        if validatesGraph {
            try updatedGraph.validate(tolerance: tolerance)
        }
        self = updatedGraph
        return feature.id
    }

    @discardableResult
    mutating func replaceFeature(
        _ feature: FeatureNode,
        tolerance: ModelingTolerance = .standard,
        validatesGraph: Bool = true
    ) throws -> FeatureID {
        guard nodes[feature.id] != nil,
              order.contains(feature.id) else {
            throw FeatureEvaluationError.invalidGraph("Replacement feature must already exist.")
        }

        var updatedGraph = self
        updatedGraph.nodes[feature.id] = feature
        updatedGraph.dependencies.removeAll { dependency in
            dependency.target == feature.id
        }
        updatedGraph.dependencies.append(contentsOf: feature.inputDependencyEdges)
        updatedGraph.revision = updatedGraph.revision.advanced()
        if validatesGraph {
            try updatedGraph.validate(tolerance: tolerance)
        }
        self = updatedGraph
        return feature.id
    }

    @discardableResult
    mutating func replaceFeatures(
        _ features: [FeatureNode],
        tolerance: ModelingTolerance = .standard,
        validatesGraph: Bool = true
    ) throws -> [FeatureID] {
        guard features.isEmpty == false else {
            return []
        }
        var featureIDs: [FeatureID] = []
        featureIDs.reserveCapacity(features.count)
        var replacementIDs = Set<FeatureID>()
        replacementIDs.reserveCapacity(features.count)
        for feature in features {
            let featureID = feature.id
            guard replacementIDs.insert(featureID).inserted else {
                throw FeatureEvaluationError.invalidGraph("Replacement feature IDs must be unique.")
            }
            guard nodes[featureID] != nil,
                  order.contains(featureID) else {
                throw FeatureEvaluationError.invalidGraph("Replacement features must already exist.")
            }
            featureIDs.append(featureID)
        }

        var updatedGraph = self
        for feature in features {
            updatedGraph.nodes[feature.id] = feature
        }
        updatedGraph.dependencies.removeAll { dependency in
            replacementIDs.contains(dependency.target)
        }
        updatedGraph.dependencies.append(contentsOf: features.replacementDependencyEdges)
        updatedGraph.revision = updatedGraph.revision.advanced()
        if validatesGraph {
            try updatedGraph.validate(tolerance: tolerance)
        }
        self = updatedGraph
        return featureIDs
    }
}

extension FeatureNode {
    var inputDependencyEdges: [DependencyEdge] {
        var edges: [DependencyEdge] = []
        appendInputDependencyEdges(to: &edges)
        return edges
    }

    func appendInputDependencyEdges(to edges: inout [DependencyEdge]) {
        guard inputs.isEmpty == false else {
            return
        }

        var sources = Set<FeatureID>()
        sources.reserveCapacity(inputs.count)
        for input in inputs {
            sources.insert(input.featureID)
        }
        edges.reserveCapacity(edges.count + sources.count)
        for source in sources.sorted(by: featureIDPrecedes) {
            edges.append(DependencyEdge(source: source, target: id))
        }
    }
}

private extension Array where Element == FeatureNode {
    var replacementDependencyEdges: [DependencyEdge] {
        let sortedFeatures = sorted { featureIDPrecedes($0.id, $1.id) }
        let dependencyCount = sortedFeatures.reduce(0) { partialResult, feature in
            partialResult + feature.inputs.count
        }
        var edges: [DependencyEdge] = []
        edges.reserveCapacity(dependencyCount)
        for feature in sortedFeatures {
            feature.appendInputDependencyEdges(to: &edges)
        }
        return edges
    }
}

private func featureIDPrecedes(_ lhs: FeatureID, _ rhs: FeatureID) -> Bool {
    lhs.description < rhs.description
}
