import CADIR

/// Owns finite wall clipping after the candidate bridge has geometric admission.
public protocol BridgeSurfaceWallTrimming: Sendable {
    func trim(feature: FeatureNode, candidate: EvaluationResult,
              context: EvaluationContext) throws -> EvaluationResult
}
