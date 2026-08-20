import CADCore
import CADIR
import CADTopology

/// Owns immutable, operation-scoped preparation for repeated point-in-solid queries.
struct SolidPointClassificationSessionSet: Sendable {
    private let pointClassifier: any SolidPointClassifying
    private let model: BRepModel
    private let sessions: [BodyID: any SolidPointClassificationSession]
    private let tolerance: ModelingTolerance

    init(
        bodyIDs: [BodyID],
        pointClassifier: any SolidPointClassifying,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        self.pointClassifier = pointClassifier
        self.model = model
        self.tolerance = tolerance

        guard let preparer = pointClassifier as? any SolidPointClassificationSessionPreparing else {
            sessions = [:]
            return
        }
        var preparedSessions: [BodyID: any SolidPointClassificationSession] = [:]
        for bodyID in Set(bodyIDs).sorted() {
            preparedSessions[bodyID] = try preparer.makeClassificationSession(
                in: bodyID,
                model: model,
                tolerance: tolerance
            )
        }
        sessions = preparedSessions
    }

    func classify(
        _ point: Point3D,
        in bodyID: BodyID
    ) throws -> SolidPointClassification {
        if let session = sessions[bodyID] {
            return try session.classify(point)
        }
        return try pointClassifier.classify(
            point,
            in: bodyID,
            model: model,
            tolerance: tolerance
        )
    }
}
