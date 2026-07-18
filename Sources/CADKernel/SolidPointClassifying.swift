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
