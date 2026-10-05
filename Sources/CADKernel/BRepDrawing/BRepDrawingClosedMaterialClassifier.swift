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
            let state = try original.classify(point)
            guard state == .boundary else { return state }
            for faceID in faces {
                try CurrentTaskCancellationChecker().checkCancellation()
                if try containment.contains(point, on: faceID, in: model, tolerance: tolerance) { return .inside }
            }
            return state
        }
    }

    private struct UnpreparedSession: SolidPointClassificationSession {
        let base: any SolidPointClassifying
        let bodyID: BodyID
        let model: BRepModel
        let tolerance: ModelingTolerance
        func classify(_ point: Point3D) throws -> SolidPointClassification {
            try base.classify(point, in: bodyID, model: model, tolerance: tolerance)
        }
    }

    func classify(_ point: Point3D, in bodyID: BodyID, model: BRepModel,
                  tolerance: ModelingTolerance) throws -> SolidPointClassification {
        let state = try base.classify(point, in: bodyID, model: model, tolerance: tolerance)
        guard state == .boundary else { return state }
        for faceID in coincidentFaces[bodyID] ?? [] {
            try CurrentTaskCancellationChecker().checkCancellation()
            if try containment.contains(point, on: faceID, in: model, tolerance: tolerance) { return .inside }
        }
        return state
    }

    func makeClassificationSession(in bodyID: BodyID, model: BRepModel,
                                   tolerance: ModelingTolerance) throws -> any SolidPointClassificationSession {
        let original: any SolidPointClassificationSession
        if let preparer = base as? any SolidPointClassificationSessionPreparing {
            original = try preparer.makeClassificationSession(in: bodyID, model: model, tolerance: tolerance)
        } else {
            original = UnpreparedSession(base: base, bodyID: bodyID, model: model, tolerance: tolerance)
        }
        return Session(original: original, bodyID: bodyID, faces: coincidentFaces[bodyID] ?? [],
            model: model, tolerance: tolerance, containment: containment)
    }
}
