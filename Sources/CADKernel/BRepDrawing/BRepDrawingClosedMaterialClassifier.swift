import CADGeometry
import CADCore
import CADIR
import CADTopology

/// Preserves original volume classification and admits the closed area of exact coplanar caps.
struct BRepDrawingClosedMaterialClassifier: SolidPointClassifying, SolidPointClassificationSessionPreparing {
    let base: any SolidPointClassifying
    let coincidentFaces: [BodyID: Set<FaceID>]
    let containment: any FacePointContainmentTesting

    private struct Session: SolidPointClassificationSession {
        let original: any SolidPointClassificationSession
        let bodyID: BodyID
        let faces: Set<FaceID>
        let model: BRepModel
        let tolerance: ModelingTolerance
        let containment: any FacePointContainmentTesting

        func classify(_ point: Point3D) throws -> SolidPointClassification {
            var execution = try OriginalQueryExecution.independentGeometry()
            return try classify(point, using: &execution)
        }


        func classify(_ point: Point3D, using execution: inout OriginalQueryExecution) throws -> SolidPointClassification {
            try execution.consumeWork(1)
            let state = try original.classify(point, using: &execution)
            guard state == .boundary else { return state }
            for faceID in faces {
                try execution.consumeWork(1)
                if try containment.contains(point, on: faceID, in: model, tolerance: tolerance, using: &execution) { return .inside }
            }
            return state
        }
    }



    func classify(_ point: Point3D, in bodyID: BodyID, model: BRepModel,
                  tolerance: ModelingTolerance) throws -> SolidPointClassification {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try classify(point, in: bodyID, model: model, tolerance: tolerance, using: &execution)
    }


    func classify(_ point: Point3D, in bodyID: BodyID, model: BRepModel,
                  tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> SolidPointClassification {
        try execution.consumeWork(1)
        let state = try base.classify(point, in: bodyID, model: model, tolerance: tolerance, using: &execution)
        guard state == .boundary else { return state }
        for faceID in coincidentFaces[bodyID] ?? [] {
            try execution.consumeWork(1)
            if try containment.contains(point, on: faceID, in: model, tolerance: tolerance, using: &execution) { return .inside }
        }
        return state
    }

    func makeClassificationSession(in bodyID: BodyID, model: BRepModel,
                                   tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> any SolidPointClassificationSession {
        try execution.consumeWork(1)
        try execution.retainStorage(bytes: MemoryLayout<Session>.stride)
        let original: any SolidPointClassificationSession
        original = try base.preparedClassificationSession(in: bodyID, model: model,
            tolerance: tolerance, using: &execution)
        return Session(original: original, bodyID: bodyID, faces: coincidentFaces[bodyID] ?? [],
            model: model, tolerance: tolerance, containment: containment)
    }
    func preparedClassificationSession(in bodyID: BodyID, validatedModel: ValidatedBRepModel,
        using execution: inout OriginalQueryExecution) throws -> any SolidPointClassificationSession {
        try makeClassificationSession(in: bodyID, model: validatedModel.model,
            tolerance: validatedModel.tolerance, using: &execution)
    }

    func preparedClassificationSession(in bodyID: BodyID, model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
        throws -> any SolidPointClassificationSession {
        try makeClassificationSession(in: bodyID, model: model, tolerance: tolerance, using: &execution)
    }

}
