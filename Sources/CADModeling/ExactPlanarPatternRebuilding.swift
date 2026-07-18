import CADCore
import CADIR

package protocol ExactPlanarPatternRebuilding: Sendable {
    func rebuild(
        featureID: FeatureID,
        sourceBodyID: BodyID,
        transforms: [ExactPatternTransform],
        stablePrefix: String,
        context: EvaluationContext
    ) throws -> EvaluationResult
}
