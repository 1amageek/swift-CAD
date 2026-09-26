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

    /// The source body rebuilt once at `transform`, replacing the source body in the model. The
    /// result's subshapes live under `featureID` and its lineage leads back to the source body.
    func relocate(
        featureID: FeatureID,
        sourceBodyID: BodyID,
        transform: ExactPatternTransform,
        stablePrefix: String,
        context: EvaluationContext
    ) throws -> EvaluationResult
}
