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

protocol FacePointContainmentSession: Sendable {
    func contains(_ point: Point3D, on faceID: FaceID) throws -> Bool
}

protocol FacePointContainmentSessionPreparing: Sendable {
    func makeContainmentSession(
        for faceIDs: [FaceID],
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> any FacePointContainmentSession
}

protocol FacePointContainmentPreparationCaching: FacePointContainmentTesting {
    func contains(
        _ point: Point3D,
        on faceID: FaceID,
        in model: BRepModel,
        preparationCache: inout FacePointContainmentPreparationCache,
        tolerance: ModelingTolerance
    ) throws -> Bool
}
