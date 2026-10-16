import CADCore
import CADGeometry
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
    ,
        using execution: inout OriginalQueryExecution
    ) throws {
        try tolerance.validate()
        self.pointClassifier = pointClassifier
        self.model = model
        self.tolerance = tolerance

        var preparedSessions: [BodyID: any SolidPointClassificationSession] = [:]
        try execution.retainKernelValues(count: bodyIDs.count,
            stride: MemoryLayout<BodyID>.stride + MemoryLayout<(BodyID, any SolidPointClassificationSession)>.stride)
        try execution.consumeWork(bodyIDs.count)
        for bodyID in Set(bodyIDs).sorted() {
            try execution.consumeWork(1)
            preparedSessions[bodyID] = try pointClassifier.preparedClassificationSession(
                in: bodyID,
                model: model,
                tolerance: tolerance, using: &execution
            )
        }
        sessions = preparedSessions
    }

    func classify(
        _ point: Point3D,
        in bodyID: BodyID
    ,
        using execution: inout OriginalQueryExecution
    ) throws -> SolidPointClassification {
        if let session = sessions[bodyID] {
            return try session.classify(point, using: &execution)
        }
        return try pointClassifier.classify(
            point,
            in: bodyID,
            model: model,
            tolerance: tolerance, using: &execution
        )
    }
}
