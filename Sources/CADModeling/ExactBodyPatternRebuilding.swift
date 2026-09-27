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

    /// The source sheet placed at every one of `transforms`, each instance its own shell of one
    /// sheet body replacing the source. Sheets are never united, so the caller proves the
    /// instances do not meet.
    func placeSheetInstancesApart(
        featureID: FeatureID,
        sourceBodyID: BodyID,
        transforms: [ExactPatternTransform],
        stablePrefix: String,
        context: EvaluationContext
    ) throws -> EvaluationResult

    /// The source body joined with its `reflection` across the plane it lies against, replacing the
    /// source body. The source lies on one side of the plane, so the two meet only on it: their
    /// faces on the plane are dropped and the rest are sewn into one shell.
    func glueReflection(
        featureID: FeatureID,
        sourceBodyID: BodyID,
        reflection: ExactPatternTransform,
        planeOrigin: Point3D,
        planeNormal: Vector3D,
        stablePrefix: String,
        context: EvaluationContext
    ) throws -> EvaluationResult
}
