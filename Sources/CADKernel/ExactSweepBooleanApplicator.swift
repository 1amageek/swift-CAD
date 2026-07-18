import CADCore
import CADIR
import CADModeling
import CADTopology

struct ExactSweepBooleanApplicator: SweepBooleanApplying {
    private let evaluator: any BRepBooleanEvaluating

    init(evaluator: any BRepBooleanEvaluating = ExactBRepBooleanEvaluator()) {
        self.evaluator = evaluator
    }

    func apply(
        operation: SweepBooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        keepTools: Bool,
        featureID: FeatureID,
        toolResult: EvaluationResult,
        targetSubshapes: [SubshapeID: TopologyReference],
        inputLineage: [SubshapeID: TopologyLineage],
        tolerance: ModelingTolerance
    ) throws -> EvaluationResult {
        try BooleanPipeline(evaluator: evaluator).evaluate(
            operation: try operation.booleanOperation(tolerance: tolerance),
            targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID,
            keepTools: keepTools,
            featureID: featureID,
            model: toolResult.brep,
            subshapes: targetSubshapes,
            toolSubshapes: toolResult.subshapes,
            inputLineage: inputLineage,
            tolerance: tolerance
        )
    }
}

private extension SweepBooleanOperation {
    func booleanOperation(tolerance: ModelingTolerance) throws -> BooleanOperation {
        switch self {
        case .newBody:
            throw KernelError(
                phase: .evaluation,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A new-body sweep must not invoke the Boolean applicator."
            )
        case .union:
            return .union
        case .difference:
            return .difference
        case .intersect:
            return .intersect
        case .slice:
            return .slice
        }
    }
}
