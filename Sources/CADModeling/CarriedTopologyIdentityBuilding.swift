import CADCore
import CADGeometry
import CADIR
import CADTopology

package protocol CarriedTopologyIdentityBuilding: Sendable {
    func identity(
        featureID: FeatureID,
        bodyID: BodyID,
        model: BRepModel,
        context: EvaluationContext
    ) throws -> CarriedTopologyIdentity
    func identity(featureID: FeatureID, bodyID: BodyID, model: BRepModel,
        context: EvaluationContext, using execution: inout OriginalQueryExecution
    ) throws -> CarriedTopologyIdentity

}
