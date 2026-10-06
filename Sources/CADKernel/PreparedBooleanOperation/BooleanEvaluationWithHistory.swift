import CADCore
import CADIR
import CADModeling
import CADTopology

/// The production exact result and its complete inverse source correspondence.
public struct BooleanEvaluationWithHistory: Sendable {
    public let result: EvaluationResult
    public let history: BooleanTopologyHistory
}

public extension PreparedBooleanIntersection {
    func evaluateWithHistory(operation: BooleanOperation, keepTools: Bool = false, featureID: FeatureID,
                             subshapes: [SubshapeID: TopologyReference],
                             toolSubshapes: [SubshapeID: TopologyReference] = [:],
                             inputLineage: [SubshapeID: TopologyLineage] = [:],
                             materials: BooleanMaterials = .default) throws -> BooleanEvaluationWithHistory {
        let result = try evaluate(operation: operation, keepTools: keepTools, featureID: featureID,
            subshapes: subshapes, toolSubshapes: toolSubshapes, inputLineage: inputLineage, materials: materials)
        return BooleanEvaluationWithHistory(result: result,
            history: try BooleanTopologyHistory(result: result,
                inputSubshapes: subshapes.merging(toolSubshapes) { first, _ in first }, tolerance: tolerance))
    }
}
