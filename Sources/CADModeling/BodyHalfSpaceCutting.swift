import CADCore
import CADIR

/// Cuts a body at a plane, keeping the material on one side.
package protocol BodyHalfSpaceCutting: Sendable {
    /// The body `bodyID` intersected with the closed half-space where `(p − planeOrigin) · planeNormal`
    /// is not positive, replacing the body in the model, with its subshapes under `featureID`.
    /// Returns `nil` when the body already lies in that half-space, so there is nothing to cut, and
    /// throws when none of it does.
    func cut(
        bodyID: BodyID,
        planeOrigin: Point3D,
        planeNormal: Vector3D,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> EvaluationResult?
}
