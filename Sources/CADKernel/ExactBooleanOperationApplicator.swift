import CADCore
import CADIR
import CADModeling
import CADTopology

struct ExactBooleanOperationApplicator: BooleanOperationApplying {
    private let evaluator: any BRepBooleanEvaluating

    init(evaluator: any BRepBooleanEvaluating = ExactBRepBooleanEvaluator()) {
        self.evaluator = evaluator
    }

    func apply(
        operation: BooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        keepTools: Bool,
        featureID: FeatureID,
        model: BRepModel,
        subshapes: [SubshapeID: TopologyReference],
        toolSubshapes: [SubshapeID: TopologyReference],
        inputLineage: [SubshapeID: TopologyLineage],
        tolerance: ModelingTolerance
    ) throws -> EvaluationResult {
        try BooleanPipeline(evaluator: evaluator).evaluate(
            operation: operation,
            targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID,
            keepTools: keepTools,
            featureID: featureID,
            model: model,
            subshapes: subshapes,
            toolSubshapes: toolSubshapes,
            inputLineage: inputLineage,
            tolerance: tolerance
        )
    }
}
