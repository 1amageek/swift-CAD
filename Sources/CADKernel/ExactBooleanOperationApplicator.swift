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
        materials: BooleanMaterials,
        tolerance: ModelingTolerance
    ) throws -> EvaluationResult {
        if operation == .region {
            guard keepTools == false else {
                throw KernelError(phase: .topology, code: .invalidInput, featureID: featureID, tolerance: tolerance,
                    message: "A Region Boolean pass consumes every operand.")
            }
            return try RegionBooleanEvaluator(pipeline: BooleanPipeline(evaluator: evaluator)).evaluate(
                operandBodyIDs: targetBodyIDs + [toolBodyID],
                featureID: featureID,
                model: model,
                subshapes: subshapes,
                inputLineage: inputLineage,
                tolerance: tolerance
            )
        }
        return try BooleanPipeline(evaluator: evaluator).evaluate(
            operation: operation,
            targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID,
            keepTools: keepTools,
            featureID: featureID,
            model: model,
            subshapes: subshapes,
            toolSubshapes: toolSubshapes,
            inputLineage: inputLineage,
            materials: materials,
            tolerance: tolerance
        )
    }
}
