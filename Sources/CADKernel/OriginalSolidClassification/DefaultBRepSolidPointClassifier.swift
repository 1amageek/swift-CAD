import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct DefaultBRepSolidPointClassifier: SolidPointClassifying,
    SolidPointClassificationSessionPreparing {
    private let intersector: any CurveSurfaceIntersecting
    private let facePointContainment: any FacePointContainmentTesting
    private let admission: OriginalSolidClassificationAdmission?

    public init(
        intersector: any CurveSurfaceIntersecting = DefaultCurveSurfaceIntersector(),
        facePointContainment: any FacePointContainmentTesting = DefaultFacePointContainmentTester()
    ) {
        self.intersector = intersector
        self.facePointContainment = facePointContainment
        self.admission = nil
    }

    private init(intersector: any CurveSurfaceIntersecting,
        facePointContainment: any FacePointContainmentTesting,
        admission: OriginalSolidClassificationAdmission) {
        self.intersector = intersector
        self.facePointContainment = facePointContainment
        self.admission = admission
    }

    public func preparedClassificationSession(in bodyID: BodyID,
        validatedModel: ValidatedBRepModel, maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void
    ) throws -> any SolidPointClassificationSession {
        try consumeWork(0)
        guard validatedModel.validationLevel != .modeling else {
            throw KernelError(phase: .classification, code: .invalidInput,
                tolerance: validatedModel.tolerance,
                message: "Solid classification requires an exact original source receipt.")
        }
        let context = try OriginalSolidClassificationAdmission(
            maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork,
            tolerance: validatedModel.tolerance)
        return try Self(intersector: intersector, facePointContainment: facePointContainment,
            admission: context).makeClassificationSession(in: bodyID,
                model: validatedModel.model, tolerance: validatedModel.tolerance)
    }

    public func preparedClassificationSession(in bodyID: BodyID,
        validatedModel: ValidatedBRepModel, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, maximumAlgebraicDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?
    ) throws -> any SolidPointClassificationSession {
        try consumeWork(0)
        guard validatedModel.validationLevel != .modeling else {
            throw KernelError(phase: .classification, code: .invalidInput,
                tolerance: validatedModel.tolerance,
                message: "Solid classification requires an exact original source receipt.")
        }
        let context = try OriginalSolidClassificationAdmission(
            maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork,
            tolerance: validatedModel.tolerance, consumeStorage: consumeStorage,
            remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth)
        return try Self(intersector: intersector, facePointContainment: facePointContainment,
            admission: context).makeClassificationSession(in: bodyID,
                model: validatedModel.model, tolerance: validatedModel.tolerance)
    }

    public func classify(_ point: Point3D, in bodyID: BodyID, model: BRepModel,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void
    ) throws -> SolidPointClassification {
        try preparedClassificationSession(in: bodyID, model: model, tolerance: tolerance,
            maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork).classify(point)
    }

    public func preparedClassificationSession(in bodyID: BodyID, model: BRepModel,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void
    ) throws -> any SolidPointClassificationSession {
        let context = try OriginalSolidClassificationAdmission(
            maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork,
            tolerance: tolerance)
        return try Self(intersector: intersector, facePointContainment: facePointContainment,
            admission: context).makeClassificationSession(in: bodyID, model: model, tolerance: tolerance)
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

    public func preparedClassificationSession(
        in bodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> (any SolidPointClassificationSession)? {
        try makeClassificationSession(in: bodyID, model: model, tolerance: tolerance)
    }

    func makeClassificationSession(
        in bodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> any SolidPointClassificationSession {
        try admission?.consume()
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
        let legacyBounds: BoundingBox3D?
        if admission?.remainingSourceDepth != nil {
            // Selected preparation derives the body bound from the same paid
            // per-face original bounds retained below, without a second source pass.
            legacyBounds = nil
        } else if let admission {
            legacyBounds = try BRepBodyBoundingBoxBuilder().bounds(for: bodyID, in: model,
                tolerance: tolerance, maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
                consumeWork: admission.consumeWork)
        } else {
            legacyBounds = try BRepBodyBoundingBoxBuilder().bounds(for: bodyID, in: model, tolerance: tolerance)
        }
        var selectedBounds: BoundingBox3D?
        var faceBounds: [FaceID: BoundingBox3D] = [:]
        for faceID in faceIDs {
            try admission?.consume()
            if let admission, let sourceDepth = admission.remainingSourceDepth {
                faceBounds[faceID] = try BRepFaceBoundingBoxBuilder().bounds(for: faceID, in: model,
                    tolerance: tolerance, maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
                    remainingSourceDepth: sourceDepth, maximumAlgebraicDepth: admission.maximumAlgebraicDepth,
                    consumeWork: admission.consumeWork, consumeStorage: admission.consumeStorage)
            } else if let admission {
                faceBounds[faceID] = try BRepFaceBoundingBoxBuilder().bounds(for: faceID, in: model,
                    tolerance: tolerance, maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
                    consumeWork: admission.consumeWork)
            } else {
                faceBounds[faceID] = try BRepFaceBoundingBoxBuilder().bounds(for: faceID, in: model,
                    tolerance: tolerance)
            }
            if admission?.remainingSourceDepth != nil, let next = faceBounds[faceID] {
                try admission?.consume()
                selectedBounds = try selectedBounds.map { try $0.union(next) } ?? next
            }
        }
        guard let bounds = legacyBounds ?? selectedBounds else {
            throw KernelError(phase: .classification, code: .topologyFailure, tolerance: tolerance,
                message: "Original solid preparation has no complete retained face bound.")
        }
        var faceParameterBounds: [FaceID: SurfaceParameterBox] = [:]
        for faceID in faceIDs {
            try Task.checkCancellation()
            try admission?.consume()
            guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference("Prepared solid classification face support is missing.")
            }
            faceParameterBounds[faceID] = try BRepRayFaceCrossings.parameterBounds(
                for: faceID, surface: surface, model: model, tolerance: tolerance,
                maximumSubdivisionDepth: admission?.maximumSubdivisionDepth ?? 48,
                consumeWork: admission?.consumeWork, consumeStorage: admission?.consumeStorage,
                remainingSourceDepth: admission?.remainingSourceDepth ?? 16,
                maximumAlgebraicDepth: admission?.maximumAlgebraicDepth ?? 32)
        }
        let containmentSession: (any FacePointContainmentSession)?
        if let admission, let sourceDepth = admission.remainingSourceDepth {
            containmentSession = try facePointContainment.preparedContainmentSession(for: faceIDs,
                in: model, tolerance: tolerance,
                maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
                remainingSourceDepth: sourceDepth, maximumAlgebraicDepth: admission.maximumAlgebraicDepth,
                consumeWork: admission.consumeWork, consumeStorage: admission.consumeStorage)
        } else if let admission {
            containmentSession = try facePointContainment.preparedContainmentSession(for: faceIDs,
                in: model, tolerance: tolerance,
                maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
                consumeWork: admission.consumeWork)
        } else {
            containmentSession = try facePointContainment.preparedContainmentSession(for: faceIDs,
                in: model, tolerance: tolerance)
        }
        return Session(
            classifier: self,
            model: model,
            faceIDs: faceIDs,
            bounds: bounds,
            faceBounds: faceBounds,
            faceParameterBounds: faceParameterBounds,
            containmentSession: containmentSession,
            tolerance: tolerance
        )
    }

    private var crossings: BRepRayFaceCrossings {
        BRepRayFaceCrossings(intersector: intersector, facePointContainment: facePointContainment,
            maximumSubdivisionDepth: admission?.maximumSubdivisionDepth,
            consumeWork: admission?.consumeWork, consumeStorage: admission?.consumeStorage,
            remainingSourceDepth: admission?.remainingSourceDepth,
            maximumAlgebraicDepth: admission?.maximumAlgebraicDepth ?? 32)
    }

    private func classify(
        _ point: Point3D,
        model: BRepModel,
        faceIDs: [FaceID],
        bounds: BoundingBox3D,
        faceBounds: [FaceID: BoundingBox3D],
        faceParameterBounds: [FaceID: SurfaceParameterBox],
        containmentSession: (any FacePointContainmentSession)?,
        tolerance: ModelingTolerance
    ) throws -> SolidPointClassification {
        try admission?.consume()
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
            try admission?.consume()
            do {
                let crossingCount = try crossings.crossings(
                    from: point,
                    direction: direction,
                    upperBound: rayUpperBound,
                    faceIDs: faceIDs,
                    model: model,
                    containmentSession: containmentSession,
                    faceParameterBounds: faceParameterBounds,
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
        throw KernelError(
            phase: .classification,
            code: .classificationFailure,
            residual: Double(classifications.count),
            tolerance: tolerance,
            message: "Complete original ray casts did not produce a consistent solid classification."
        )
    }

    private func faceIDs(
        for body: Body,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> [FaceID] {
        var result: [FaceID] = []
        for shellID in body.shellIDs {
            try admission?.consume()
            guard let shell = model.shells[shellID] else {
                throw KernelError(
                    phase: .classification,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Point-in-solid classification references a missing shell."
                )
            }
            for faceID in shell.faceIDs {
                try admission?.consume()
                result.append(faceID)
            }
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
        let faceParameterBounds: [FaceID: SurfaceParameterBox]
        let containmentSession: (any FacePointContainmentSession)?
        let tolerance: ModelingTolerance

        func originalSpatialBounds() throws -> BoundingBox3D? {
            try classifier.admission?.consume()
            try Task.checkCancellation()
            return bounds
        }

        func classify(_ point: Point3D) throws -> SolidPointClassification {
            try classifier.classify(
                point,
                model: model,
                faceIDs: faceIDs,
                bounds: bounds,
                faceBounds: faceBounds,
                faceParameterBounds: faceParameterBounds,
                containmentSession: containmentSession,
                tolerance: tolerance
            )
        }
    }
}
