import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct DefaultBRepSolidPointClassifier: SolidPointClassifying,
    SolidPointClassificationSessionPreparing {
    private let intersector: any CurveSurfaceIntersecting
    private let facePointContainment: any FacePointContainmentTesting

    public init(intersector: any CurveSurfaceIntersecting = DefaultCurveSurfaceIntersector(),
        facePointContainment: any FacePointContainmentTesting = DefaultFacePointContainmentTester()) {
        self.intersector = intersector; self.facePointContainment = facePointContainment
    }

    public func preparedClassificationSession(in bodyID: BodyID,
        validatedModel: ValidatedBRepModel, using execution: inout OriginalQueryExecution)
        throws -> any SolidPointClassificationSession {
      do {
        try execution.checkpoint()
        guard validatedModel.validationLevel != .modeling else {
            throw KernelError(phase: .classification, code: .invalidInput,
                tolerance: validatedModel.tolerance,
                message: "Solid classification requires an exact original source receipt.")
        }
        return try makeClassificationSession(in: bodyID, model: validatedModel.model,
            tolerance: validatedModel.tolerance, using: &execution)

      } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: validatedModel.tolerance) }
    }

    public func classify(_ point: Point3D, in bodyID: BodyID, model: BRepModel,
        tolerance: ModelingTolerance) throws -> SolidPointClassification {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try classify(point, in: bodyID, model: model, tolerance: tolerance, using: &execution)
    }

    public func classify(_ point: Point3D, in bodyID: BodyID, model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
        throws -> SolidPointClassification {
      do {
        let session = try makeClassificationSession(in: bodyID, model: model,
            tolerance: tolerance, using: &execution)
        return try session.classify(point, using: &execution)

      } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance) }
    }

    public func preparedClassificationSession(in bodyID: BodyID, model: BRepModel,
        tolerance: ModelingTolerance) throws -> (any SolidPointClassificationSession)? {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try makeClassificationSession(in: bodyID, model: model,
            tolerance: tolerance, using: &execution)
    }

    public func preparedClassificationSession(in bodyID: BodyID, model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
        throws -> any SolidPointClassificationSession {
      do {
        return try makeClassificationSession(in: bodyID, model: model,
            tolerance: tolerance, using: &execution)

      } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance) }
    }

    func makeClassificationSession(in bodyID: BodyID, model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
        throws -> any SolidPointClassificationSession {
        let caps = try OriginalQueryExecutionLimits(maximumValueDepth: 32,
            maximumCoefficientDepth: 32, remainingSourceDepth: 16,
            maximumSubdivisionDepth: 48)
        let contribution = try execution.makeContributionHandle(executionLimits: caps)
        return try execution.withContributionScope(contribution) { execution in
            let prepared = try execution.withPreparationScope { execution in
                try prepare(in: bodyID, model: model, tolerance: tolerance, using: &execution)
            }
            let lifetime = try PreparedBooleanQueryLifetime.retain(depth: prepared.depth, using: &execution)
            try execution.retainStorage(bytes: MemoryLayout<Session.Payload>.stride
                + 2 * MemoryLayout<UnsafeRawPointer>.stride)
            let session = Session(payload: .init(prepared: prepared.result, lifetime: lifetime))
            try execution.checkpoint()
            return session
        }
    }

    private func prepare(in bodyID: BodyID, model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
        throws -> Preparation {
        execution.context = execution.context.at(stage: .source)
        try execution.consumeWork(1); try tolerance.validate()
        guard let body = model.bodies[bodyID], body.kind == .solid else {
            throw KernelError(phase: .classification, code: .missingReference, tolerance: tolerance,
                message: "Point-in-solid classification requires a solid body.")
        }
        let faceIDs = try faceIDs(for: body, model: model, tolerance: tolerance, using: &execution)
        let limits = execution.effectiveLimits
        let geometricDepth = min(48, limits.maximumSubdivisionDepth)
        let sourceDepth = min(16, limits.remainingSourceDepth)
        let algebraDepth = min(32, limits.maximumValueDepth, limits.maximumCoefficientDepth)
        var bounds: BoundingBox3D?
        try execution.retainKernelValues(count: faceIDs.count,
            stride: MemoryLayout<(FaceID, BoundingBox3D)>.stride
                + MemoryLayout<(FaceID, SurfaceParameterBox)>.stride)
        var faceBounds: [FaceID: BoundingBox3D] = [:]
        var faceParameterBounds: [FaceID: SurfaceParameterBox] = [:]
        for faceID in faceIDs {
            execution.context = execution.context.at(stage: .source)
            try execution.consumeWork(1)
            let builder = BRepFaceBoundingBoxBuilder()
            let next = try builder.bounds(for: faceID, in: model, tolerance: tolerance,
                maximumSubdivisionDepth: min(32, geometricDepth), remainingSourceDepth: sourceDepth,
                maximumAlgebraicDepth: algebraDepth, using: &execution)
            faceBounds[faceID] = next
            bounds = try bounds.map { try $0.union(next) } ?? next
            guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference("Prepared solid classification face support is missing.")
            }
            faceParameterBounds[faceID] = try BRepRayFaceCrossings.parameterBounds(for: faceID,
                surface: surface, model: model, tolerance: tolerance,
                maximumSubdivisionDepth: geometricDepth, remainingSourceDepth: sourceDepth,
                maximumAlgebraicDepth: algebraDepth, using: &execution)
        }
        guard let bounds else {
            throw KernelError(phase: .classification, code: .topologyFailure, tolerance: tolerance,
                message: "Original solid preparation has no complete retained face bound.")
        }
        let containment = try facePointContainment.preparedContainmentSession(for: faceIDs,
            in: model, tolerance: tolerance, using: &execution)
        return .init(classifier: self, model: model, faceIDs: faceIDs, bounds: bounds,
            faceBounds: faceBounds, faceParameterBounds: faceParameterBounds,
            containmentSession: containment, tolerance: tolerance)
    }

    private var crossings: BRepRayFaceCrossings {
        .init(intersector: intersector, facePointContainment: facePointContainment)
    }

    private func classify(
        _ point: Point3D,
        model: BRepModel,
        faceIDs: [FaceID],
        bounds: BoundingBox3D,
        faceBounds: [FaceID: BoundingBox3D],
        faceParameterBounds: [FaceID: SurfaceParameterBox],
        containmentSession: (any FacePointContainmentSession)?,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> SolidPointClassification {
        try execution.consumeWork(1)
        try point.validate()
        if try crossings.liesOnFace(
            point, faceIDs: faceIDs, faceBounds: faceBounds, model: model,
            containmentSession: containmentSession, tolerance: tolerance, using: &execution
        ) {
            return .boundary
        }
        let rayUpperBound = crossings.upperBound(from: point, bounds: bounds, tolerance: tolerance)
        let directions = try BRepRayFaceCrossings.directions(tolerance: tolerance)
        var classifications: [SolidPointClassification] = []
        for direction in directions {
            try execution.consumeWork(1)
            do {
                let crossingCount = try crossings.crossings(
                    from: point,
                    direction: direction,
                    upperBound: rayUpperBound,
                    faceIDs: faceIDs,
                    model: model,
                    containmentSession: containmentSession,
                    faceParameterBounds: faceParameterBounds,
                    tolerance: tolerance, using: &execution
                ).count
                try OriginalParameterQueryStorage.append(
                    crossingCount.isMultiple(of: 2) ? .outside : .inside,
                    to: &classifications, using: &execution)
            } catch let error where OriginalQueryFailure.classification(of: error)?.code == .nonDiscreteIntersection {
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> [FaceID] {
        var result: [FaceID] = []
        for shellID in body.shellIDs {
            try execution.consumeWork(1)
            guard let shell = model.shells[shellID] else {
                throw KernelError(
                    phase: .classification,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Point-in-solid classification references a missing shell."
                )
            }
            try execution.retainKernelValues(count: shell.faceIDs.count, stride: MemoryLayout<FaceID>.stride)
            for faceID in shell.faceIDs {
                try execution.consumeWork(1)
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

    private struct Preparation: Sendable {
        let classifier: DefaultBRepSolidPointClassifier
        let model: BRepModel
        let faceIDs: [FaceID]
        let bounds: BoundingBox3D
        let faceBounds: [FaceID: BoundingBox3D]
        let faceParameterBounds: [FaceID: SurfaceParameterBox]
        let containmentSession: any FacePointContainmentSession
        let tolerance: ModelingTolerance
    }

    private final class Session: SolidPointClassificationSession {
        struct Payload: Sendable {
            let prepared: Preparation
            let lifetime: PreparedBooleanQueryLifetime
        }
        let payload: Payload
        init(payload: Payload) { self.payload = payload }

        func originalSpatialBounds() throws -> BoundingBox3D? {
            var execution = try payload.lifetime.execution()
            return try originalSpatialBounds(using: &execution)
        }
        func originalSpatialBounds(using execution: inout OriginalQueryExecution) throws -> BoundingBox3D? {
            try payload.lifetime.withRead(using: &execution) { execution in
                try execution.consumeWork(1)
                return payload.prepared.bounds
            }
        }
        func classify(_ point: Point3D) throws -> SolidPointClassification {
            var execution = try payload.lifetime.execution()
            return try classify(point, using: &execution)
        }
        func classify(_ point: Point3D, using execution: inout OriginalQueryExecution)
            throws -> SolidPointClassification {
            do {
                return try payload.lifetime.withRead(using: &execution) { execution in
                let p = payload.prepared
                let result = try p.classifier.classify(point, model: p.model, faceIDs: p.faceIDs,
                    bounds: p.bounds, faceBounds: p.faceBounds, faceParameterBounds: p.faceParameterBounds,
                    containmentSession: p.containmentSession, tolerance: p.tolerance, using: &execution)
                try execution.checkpoint()
                return result
                }
            } catch { throw OriginalQueryFailure.published(error, context: execution.context,
                tolerance: payload.prepared.tolerance) }
        }
    }
}
