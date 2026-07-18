import CADCore

public struct ValidatedCADDocument: Sendable {
    public let document: CADDocument
    public let tolerance: ModelingTolerance
    package let identity: ValidatedCADDocumentIdentity
    package let transition: ValidatedCADDocumentTransition?

    public init(
        _ document: CADDocument,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        try document.validate(tolerance: tolerance)
        self.document = document
        self.tolerance = tolerance
        identity = ValidatedCADDocumentIdentity()
        transition = nil
    }

    public func replacingGraphStableFeature(
        _ feature: FeatureNode
    ) throws -> ValidatedCADDocument {
        try replacingGraphStableFeatures([feature])
    }

    public func replacingGraphStableFeatures(
        _ features: [FeatureNode]
    ) throws -> ValidatedCADDocument {
        guard !features.isEmpty else {
            return self
        }

        var changedFeatureIDs = Set<FeatureID>()
        changedFeatureIDs.reserveCapacity(features.count)
        for feature in features {
            guard changedFeatureIDs.insert(feature.id).inserted else {
                throw FeatureEvaluationError.invalidGraph(
                    "Replacement feature IDs must be unique."
                )
            }
            guard let previousFeature = document.designGraph.nodes[feature.id] else {
                throw FeatureEvaluationError.invalidGraph(
                    "Replacement features must already exist in the validated document."
                )
            }
            guard feature.inputs == previousFeature.inputs,
                  feature.outputs == previousFeature.outputs,
                  feature.isSuppressed == previousFeature.isSuppressed else {
                throw FeatureEvaluationError.invalidGraph(
                    "Graph-stable replacement cannot change inputs, outputs, or suppression."
                )
            }
        }

        var updatedDocument = document
        for feature in features {
            updatedDocument.designGraph.nodes[feature.id] = feature
        }
        updatedDocument.designGraph.revision = updatedDocument.designGraph.revision.advanced()
        try updatedDocument.designGraph.revision.validate()
        for feature in features {
            try updatedDocument.designGraph.validateOperationContract(
                for: feature,
                tolerance: tolerance
            )
            try updatedDocument.designGraph.validateExpressions(
                for: feature,
                using: updatedDocument.parameters,
                tolerance: tolerance
            )
        }
        return ValidatedCADDocument(
            validatedDocument: updatedDocument,
            tolerance: tolerance,
            transition: ValidatedCADDocumentTransition(
                sourceIdentity: identity,
                changedFeatureIDs: changedFeatureIDs
            )
        )
    }

    public func appendingFeatures(
        _ features: [FeatureNode]
    ) throws -> ValidatedCADDocument {
        guard !features.isEmpty else {
            return self
        }

        var updatedDocument = document
        try updatedDocument.designGraph.appendFeatures(
            features,
            tolerance: tolerance,
            validatesGraph: false
        )
        try updatedDocument.designGraph.revision.validate()

        var appendedIndices: [FeatureID: Int] = [:]
        appendedIndices.reserveCapacity(features.count)
        for (offset, feature) in features.enumerated() {
            appendedIndices[feature.id] = document.designGraph.order.count + offset
        }

        for feature in features {
            guard let targetIndex = appendedIndices[feature.id] else {
                throw FeatureEvaluationError.invalidGraph(
                    "Appended feature order is incomplete."
                )
            }
            try updatedDocument.designGraph.validateOperationContract(
                for: feature,
                tolerance: tolerance
            )
            try updatedDocument.designGraph.validateExpressions(
                for: feature,
                using: updatedDocument.parameters,
                tolerance: tolerance
            )
            for input in feature.inputs {
                guard let source = updatedDocument.designGraph.nodes[input.featureID] else {
                    throw FeatureEvaluationError.invalidGraph(
                        "Feature input references a missing node."
                    )
                }
                if let sourceIndex = appendedIndices[input.featureID] {
                    guard sourceIndex < targetIndex else {
                        throw FeatureEvaluationError.invalidGraph(
                            "Feature input must appear before the consuming feature."
                        )
                    }
                }
                guard feature.isSuppressed || !source.isSuppressed else {
                    throw FeatureEvaluationError.invalidGraph(
                        "Active feature input references a suppressed feature."
                    )
                }
            }
        }

        return ValidatedCADDocument(
            validatedDocument: updatedDocument,
            tolerance: tolerance,
            transition: nil
        )
    }

    private init(
        validatedDocument document: CADDocument,
        tolerance: ModelingTolerance,
        transition: ValidatedCADDocumentTransition?
    ) {
        self.document = document
        self.tolerance = tolerance
        identity = ValidatedCADDocumentIdentity()
        self.transition = transition
    }
}
