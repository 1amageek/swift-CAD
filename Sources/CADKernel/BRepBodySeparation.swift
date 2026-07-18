import CADCore
import CADGeometry
import CADIR

struct BRepBodySeparation: Sendable {
    let negativeBodyID: BodyID
    let positiveBodyID: BodyID
    let direction: Vector3D
    let negativeMaximum: Double
    let positiveMinimum: Double

    init(
        negativeBodyID: BodyID,
        positiveBodyID: BodyID,
        direction: Vector3D,
        negativeMaximum: Double,
        positiveMinimum: Double,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        guard negativeBodyID != positiveBodyID,
              negativeMaximum.isFinite,
              positiveMinimum.isFinite,
              positiveMinimum > negativeMaximum + tolerance.distance else {
            throw KernelError.unsupportedEvaluation(
                tolerance: tolerance,
                message: "B-rep separation witness does not contain a positive tolerance gap."
            )
        }
        self.negativeBodyID = negativeBodyID
        self.positiveBodyID = positiveBodyID
        self.direction = try direction.normalized(tolerance: tolerance.distance)
        self.negativeMaximum = negativeMaximum
        self.positiveMinimum = positiveMinimum
    }

    func validate(
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        guard targetBodyIDs.count == 1,
              Set([targetBodyIDs[0], toolBodyID]) == Set([negativeBodyID, positiveBodyID]),
              positiveMinimum > negativeMaximum + tolerance.distance else {
            throw KernelError.unsupportedEvaluation(
                tolerance: tolerance,
                message: "B-rep separation witness does not match the requested operands."
            )
        }
    }
}
