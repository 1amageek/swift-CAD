import CADCore
import CADIR
import CADTopology

public protocol FacePointContainmentTesting: Sendable {
    func contains(
        _ point: Point3D,
        on faceID: FaceID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Bool
}
