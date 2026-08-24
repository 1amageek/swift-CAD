import CADCore
import CADGeometry
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

protocol FaceParameterContainmentSession: Sendable {
    func contains(_ parameter: SurfaceParameter, on faceID: FaceID) throws -> Bool
}

protocol FaceParameterContainmentSessionPreparing: Sendable {
    func makeParameterContainmentSession(
        for faceIDs: [FaceID],
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> any FaceParameterContainmentSession
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

protocol FaceParameterContainmentPreparationCaching: Sendable {
    func contains(
        _ parameter: SurfaceParameter,
        on faceID: FaceID,
        in model: BRepModel,
        preparationCache: inout FacePointContainmentPreparationCache,
        tolerance: ModelingTolerance
    ) throws -> Bool
}
