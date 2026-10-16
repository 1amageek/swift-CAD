import CADCore
import CADGeometry
import CADTopology

protocol FaceSpatialBoundsResolving: Sendable {
    func bounds(
        for faceID: FaceID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BoundingBox3D

    func bounds(for faceID: FaceID, in model: BRepModel, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> BoundingBox3D
}
