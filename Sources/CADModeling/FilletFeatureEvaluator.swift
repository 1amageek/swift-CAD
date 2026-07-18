import CADCore
import CADIR

public struct FilletFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let edgeBlendEvaluator: EdgeBlendFeatureEvaluator

    public init(
        resolver: ParameterResolving = ParameterResolver(),
        subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver(),
        sewer: any BRepSewing = DefaultBRepSewer()
    ) {
        edgeBlendEvaluator = EdgeBlendFeatureEvaluator(
            resolver: resolver,
            subshapeResolver: subshapeResolver,
            sewer: sewer
        )
    }

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    package func evaluateValidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> ValidatedFeatureEvaluation {
        try context.tolerance.validate()
        let result = try edgeBlendEvaluator.evaluateFillet(feature: feature, context: context)
        return try ValidatedFeatureEvaluation(
            validating: result,
            tolerance: context.tolerance
        )
    }
}
