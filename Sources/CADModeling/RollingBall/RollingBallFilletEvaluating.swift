import CADIR

/// The kernel composes retained solid faces; modeling owns the ordinary feature route.
public protocol RollingBallFilletEvaluating: Sendable {
    func admits(feature: FeatureNode, context: EvaluationContext) throws -> Bool
    func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult
}
