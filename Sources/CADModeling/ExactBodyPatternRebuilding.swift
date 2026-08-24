import CADCore
import CADIR

package protocol ExactBodyPatternRebuilding: Sendable {
    func rebuild(
        featureID: FeatureID,
        sourceBodyID: BodyID,
        transforms: [ExactPatternTransform],
        stablePrefix: String,
        context: EvaluationContext
    ) throws -> EvaluationResult
}
