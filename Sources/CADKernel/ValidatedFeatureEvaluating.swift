import CADIR

protocol ValidatedFeatureEvaluating: FeatureEvaluating {
    func evaluateValidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> ValidatedFeatureEvaluation
}
