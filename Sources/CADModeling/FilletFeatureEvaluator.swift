import CADCore
import CADIR

public struct FilletFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let edgeBlendEvaluator: EdgeBlendFeatureEvaluator

    public init(
        sewer: any BRepSewing,
        resolver: ParameterResolving = ParameterResolver(),
        subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver()
    ) {
        edgeBlendEvaluator = EdgeBlendFeatureEvaluator(
            sewer: sewer,
            resolver: resolver,
            subshapeResolver: subshapeResolver
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
