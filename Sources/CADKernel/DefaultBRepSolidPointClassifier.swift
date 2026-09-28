import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct DefaultBRepSolidPointClassifier: SolidPointClassifying,
    SolidPointClassificationSessionPreparing {
    private let intersector: any CurveSurfaceIntersecting
    private let facePointContainment: any FacePointContainmentTesting

    public init(
        intersector: any CurveSurfaceIntersecting = DefaultCurveSurfaceIntersector(),
        facePointContainment: any FacePointContainmentTesting = DefaultFacePointContainmentTester()
    ) {
        self.intersector = intersector
        self.facePointContainment = facePointContainment
    }

    public func classify(
        _ point: Point3D,
        in bodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> SolidPointClassification {
        let session = try makeClassificationSession(
            in: bodyID,
            model: model,
            tolerance: tolerance
        )
        return try session.classify(point)
    }

    func makeClassificationSession(
        in bodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> any SolidPointClassificationSession {
        try tolerance.validate()
        guard let body = model.bodies[bodyID], body.kind == .solid else {
            throw KernelError(
                phase: .classification,
                code: .missingReference,
                tolerance: tolerance,
                message: "Point-in-solid classification requires a solid body."
            )
        }
        let faceIDs = try faceIDs(for: body, model: model, tolerance: tolerance)
        let bounds = try BRepBodyBoundingBoxBuilder().bounds(
            for: bodyID,
            in: model,
            tolerance: tolerance
        )
        let faceBounds = try Dictionary(uniqueKeysWithValues: faceIDs.map {
            faceID -> (FaceID, BoundingBox3D) in
            let bounds = try BRepFaceBoundingBoxBuilder().bounds(
                for: faceID,
                in: model,
                tolerance: tolerance
            )
            return (faceID, bounds)
        })
        let containmentSession = try (
            facePointContainment as? any FacePointContainmentSessionPreparing
        )?.makeContainmentSession(
            for: faceIDs,
            in: model,
            tolerance: tolerance
        )
        return Session(
            classifier: self,
            model: model,
            faceIDs: faceIDs,
            bounds: bounds,
            faceBounds: faceBounds,
            containmentSession: containmentSession,
            tolerance: tolerance
        )
    }

    private var crossings: BRepRayFaceCrossings {
        BRepRayFaceCrossings(intersector: intersector, facePointContainment: facePointContainment)
    }

    private func classify(
        _ point: Point3D,
        model: BRepModel,
        faceIDs: [FaceID],
        bounds: BoundingBox3D,
        faceBounds: [FaceID: BoundingBox3D],
        containmentSession: (any FacePointContainmentSession)?,
        tolerance: ModelingTolerance
    ) throws -> SolidPointClassification {
        try point.validate()
        if try crossings.liesOnFace(
            point, faceIDs: faceIDs, faceBounds: faceBounds, model: model,
            containmentSession: containmentSession, tolerance: tolerance
        ) {
            return .boundary
        }
        let rayUpperBound = crossings.upperBound(from: point, bounds: bounds, tolerance: tolerance)
        let directions = try BRepRayFaceCrossings.directions(tolerance: tolerance)
        var classifications: [SolidPointClassification] = []
        for direction in directions {
            do {
                let crossingCount = try crossings.crossings(
                    from: point,
                    direction: direction,
                    upperBound: rayUpperBound,
                    faceIDs: faceIDs,
                    model: model,
                    containmentSession: containmentSession,
                    tolerance: tolerance
                ).count
                classifications.append(crossingCount.isMultiple(of: 2) ? .outside : .inside)
            } catch let error as KernelError where error.code == .nonDiscreteIntersection {
                continue
            }
        }
        if let first = classifications.first,
           classifications.allSatisfy({ $0 == first }) {
            return first
        }
        if classifications.count == directions.count {
            let insideCount = classifications.count { $0 == .inside }
            let outsideCount = classifications.count { $0 == .outside }
            if insideCount > outsideCount {
                return .inside
            }
            if outsideCount > insideCount {
                return .outside
            }
        }
        throw KernelError(
            phase: .classification,
            code: .classificationFailure,
            residual: Double(classifications.count),
            tolerance: tolerance,
            message: "Independent analytic ray casts did not produce a majority solid classification."
        )
    }

    private func faceIDs(
        for body: Body,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> [FaceID] {
        var result: [FaceID] = []
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                throw KernelError(
                    phase: .classification,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Point-in-solid classification references a missing shell."
                )
            }
            result.append(contentsOf: shell.faceIDs)
        }
        guard result.isEmpty == false else {
            throw KernelError(
                phase: .classification,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Point-in-solid classification requires at least one face."
            )
        }
        return result
    }

    private struct Session: SolidPointClassificationSession {
        let classifier: DefaultBRepSolidPointClassifier
        let model: BRepModel
        let faceIDs: [FaceID]
        let bounds: BoundingBox3D
        let faceBounds: [FaceID: BoundingBox3D]
        let containmentSession: (any FacePointContainmentSession)?
        let tolerance: ModelingTolerance

        func classify(_ point: Point3D) throws -> SolidPointClassification {
            try classifier.classify(
                point,
                model: model,
                faceIDs: faceIDs,
                bounds: bounds,
                faceBounds: faceBounds,
                containmentSession: containmentSession,
                tolerance: tolerance
            )
        }
    }
}
