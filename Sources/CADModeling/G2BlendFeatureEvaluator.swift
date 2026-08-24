import CADCore
import CADIR

public struct G2BlendFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
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
        let result = try evaluateUnvalidated(feature: feature, context: context)
        return try ValidatedFeatureEvaluation(
            validating: result,
            tolerance: context.tolerance
        )
    }

    private func evaluateUnvalidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        try context.tolerance.validate()
        guard case let .g2Blend(blend) = feature.operation else {
            throw FeatureEvaluationError.invalidGraph(
                "G2BlendFeatureEvaluator received a non-G2-blend feature."
            )
        }
        return try edgeBlendEvaluator.evaluateG2(feature: feature, blend: blend, context: context)
    }
}
