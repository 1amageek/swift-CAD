import CADIR

/// Evaluates one feature request against an immutable modeling context.
public protocol FeatureEvaluating: Sendable {
    func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult
}
