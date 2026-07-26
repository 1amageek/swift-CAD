import CADCore
import CADIR

package protocol SurfaceOperationTargetResolving: Sendable {
    func resolve(
        _ target: SurfaceOperationTargetReference,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> ResolvedSurfaceOperationTarget
}
