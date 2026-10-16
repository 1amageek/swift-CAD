import CADIR
import CADCore
import CADGeometry

/// Owns finite wall clipping after the candidate bridge has geometric admission.
public protocol BridgeSurfaceWallTrimming: Sendable {
    func trim(feature: FeatureNode, candidate: EvaluationResult,
              context: EvaluationContext) throws -> EvaluationResult
    func trim(feature: FeatureNode, candidate: EvaluationResult,
        context: EvaluationContext, using execution: inout OriginalQueryExecution) throws -> EvaluationResult
}

extension BridgeSurfaceWallTrimming {
    public func trim(feature: FeatureNode, candidate: EvaluationResult,
        context: EvaluationContext) throws -> EvaluationResult {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try trim(feature: feature, candidate: candidate, context: context, using: &execution)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Injected Bridge wall trimmers need their
    // actual clipping and publication witness under the caller execution before
    // Bridge feature evaluation may treat this provider as supported.
    public func trim(feature: FeatureNode, candidate: EvaluationResult,
        context: EvaluationContext, using execution: inout OriginalQueryExecution) throws -> EvaluationResult {
        throw KernelError(phase: .classification, code: .unsupportedCapability, featureID: feature.id,
            tolerance: context.tolerance, message: "This Bridge wall trimmer has no direct original execution witness.")
    }
}
