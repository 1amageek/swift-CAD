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
        for faceID in faceIDs {
            if let faceBounds = faceBounds[faceID],
               faceBounds.contains(point, tolerance: tolerance.distance) == false {
                continue
            }
            do {
                if try contains(
                    point,
                    on: faceID,
                    model: model,
                    containmentSession: containmentSession,
                    tolerance: tolerance
                ) {
                    return .boundary
                }
            } catch let error as KernelError where error.code == .intersectionFailure {
                continue
            } catch GeometryError.invalidVectorLength {
                continue
            }
        }

        let rayUpperBound = try rayUpperBound(
            from: point,
            bounds: bounds,
            tolerance: tolerance
        )
        let directions = try [
            Vector3D(x: 1.0, y: 0.371_390_676_354, z: 0.618_033_988_750),
            Vector3D(x: 0.414_213_562_373, y: 1.0, z: 0.732_050_807_569),
            Vector3D(x: 0.577_215_664_902, y: 0.693_147_180_560, z: 1.0),
        ].map { try $0.normalized(tolerance: tolerance.distance) }
        var classifications: [SolidPointClassification] = []
        for direction in directions {
            do {
                let crossingCount = try crossingCount(
                    from: point,
                    direction: direction,
                    upperBound: rayUpperBound,
                    faceIDs: faceIDs,
                    model: model,
                    containmentSession: containmentSession,
                    tolerance: tolerance
                )
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

    private func crossingCount(
        from point: Point3D,
        direction: Vector3D,
        upperBound: Double,
        faceIDs: [FaceID],
        model: BRepModel,
        containmentSession: (any FacePointContainmentSession)?,
        tolerance: ModelingTolerance
    ) throws -> Int {
        let ray = Curve3D.line(Line3D(origin: point, direction: direction))
        let range = try ScalarInterval(
            lower: tolerance.distance * 2.0,
            upper: upperBound
        )
        var crossings: [Point3D] = []
        for faceID in faceIDs {
            guard let face = model.faces[faceID],
                  let surface = model.geometry.surfaces[face.surfaceID] else {
                throw KernelError(
                    phase: .classification,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Ray classification references missing face geometry."
                )
            }
            let intersections = try intersector.intersections(
                curve: ray,
                surface: surface,
                options: CurveSurfaceIntersectionOptions(
                    curveRange: range,
                    surfaceURange: try finiteInterval(surface.uDomain),
                    surfaceVRange: try finiteInterval(surface.vDomain)
                ),
                tolerance: tolerance
            )
            for intersection in intersections where intersection.kind == .transverse {
                let isContained = try containsSurfaceParameter(
                    SurfaceParameter(
                        u: intersection.surfaceU,
                        v: intersection.surfaceV
                    ),
                    fallbackPoint: intersection.point,
                    on: faceID,
                    model: model,
                    containmentSession: containmentSession,
                    tolerance: tolerance
                )
                guard isContained else {
                    continue
                }
                if crossings.contains(where: {
                    ($0 - intersection.point).length <= tolerance.distance
                }) == false {
                    crossings.append(intersection.point)
                }
            }
        }
        return crossings.count
    }

    private func rayUpperBound(
        from point: Point3D,
        bounds: BoundingBox3D,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let corners = [
            Point3D(x: bounds.minimum.x, y: bounds.minimum.y, z: bounds.minimum.z),
            Point3D(x: bounds.minimum.x, y: bounds.minimum.y, z: bounds.maximum.z),
            Point3D(x: bounds.minimum.x, y: bounds.maximum.y, z: bounds.minimum.z),
            Point3D(x: bounds.minimum.x, y: bounds.maximum.y, z: bounds.maximum.z),
            Point3D(x: bounds.maximum.x, y: bounds.minimum.y, z: bounds.minimum.z),
            Point3D(x: bounds.maximum.x, y: bounds.minimum.y, z: bounds.maximum.z),
            Point3D(x: bounds.maximum.x, y: bounds.maximum.y, z: bounds.minimum.z),
            Point3D(x: bounds.maximum.x, y: bounds.maximum.y, z: bounds.maximum.z),
        ]
        let maximumDistance = corners.map { ($0 - point).length }.max() ?? 0.0
        return max(maximumDistance * 2.0, tolerance.distance * 16.0)
    }

    private func contains(
        _ point: Point3D,
        on faceID: FaceID,
        model: BRepModel,
        containmentSession: (any FacePointContainmentSession)?,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        if let containmentSession {
            return try containmentSession.contains(point, on: faceID)
        }
        return try facePointContainment.contains(
            point,
            on: faceID,
            in: model,
            tolerance: tolerance
        )
    }

    private func containsSurfaceParameter(
        _ parameter: SurfaceParameter,
        fallbackPoint: Point3D,
        on faceID: FaceID,
        model: BRepModel,
        containmentSession: (any FacePointContainmentSession)?,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        if let parameterSession = containmentSession
            as? any FaceParameterContainmentSession {
            return try parameterSession.contains(parameter, on: faceID)
        }
        return try contains(
            fallbackPoint,
            on: faceID,
            model: model,
            containmentSession: containmentSession,
            tolerance: tolerance
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

    private func finiteInterval(_ domain: ParameterDomain) throws -> ScalarInterval? {
        switch domain {
        case let .closed(lower, upper):
            return try ScalarInterval(lower: lower, upper: upper)
        case let .periodic(period):
            return try ScalarInterval(lower: 0.0, upper: period)
        case .unbounded:
            return nil
        }
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
