import CADCore
import CADIR
import CADTopology

package protocol CarriedTopologyIdentityBuilding: Sendable {
    func identity(
        featureID: FeatureID,
        bodyID: BodyID,
        model: BRepModel,
        context: EvaluationContext
    ) throws -> CarriedTopologyIdentity
}
