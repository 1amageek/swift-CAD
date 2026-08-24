import CADCore
import CADTopology

public protocol FaceDeletionTopologyTransforming: Sendable {
    func transformedModel(
        deleting faceIDs: Set<FaceID>,
        from bodyID: BodyID,
        featureID: FeatureID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BRepModel
}
