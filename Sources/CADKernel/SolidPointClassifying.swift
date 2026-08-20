import CADCore
import CADIR
import CADTopology

public protocol SolidPointClassifying: Sendable {
    func classify(
        _ point: Point3D,
        in bodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> SolidPointClassification
}

protocol SolidPointClassificationSession: Sendable {
    func classify(_ point: Point3D) throws -> SolidPointClassification
}

protocol SolidPointClassificationSessionPreparing: Sendable {
    func makeClassificationSession(
        in bodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> any SolidPointClassificationSession
}
