import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Classifies points against a sheet body taken as solid behind its faces' normals: `inside`
/// behind the sheet, `outside` in front, `boundary` on it.
///
/// A ray from the point along a direction, or against it, meets the sheet first at some face; the
/// point is behind the sheet when the ray leaves through that face's front (the oriented normal
/// and the ray agree). The directions are the sheet's face normals at their parameter midpoints,
/// which reach a sheet that covers the point head on, then three fixed oblique directions. A
/// point no ray can reach the sheet from lies beyond the sheet's extent, and directions that
/// disagree mean the sheet folds back over the point: both are typed classification failures,
/// never a guessed side.
struct BRepSheetSidePointClassifier: SolidPointClassificationSessionPreparing {
    private let crossings: BRepRayFaceCrossings

    init(
        intersector: any CurveSurfaceIntersecting = DefaultCurveSurfaceIntersector(),
        facePointContainment: any FacePointContainmentTesting = DefaultFacePointContainmentTester()
    ) {
        crossings = BRepRayFaceCrossings(intersector: intersector, facePointContainment: facePointContainment)
    }

    func makeClassificationSession(in bodyID: BodyID, model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
        throws -> any SolidPointClassificationSession {
        do {
            let prepared = try execution.withPreparationScope { execution in
                try prepare(in: bodyID, model: model, tolerance: tolerance, using: &execution)
            }
            try execution.retainStorage(bytes: MemoryLayout<Preparation>.stride
                + 2 * MemoryLayout<UnsafeRawPointer>.stride)
            let lifetime = try PreparedBooleanQueryLifetime.retain(depth: prepared.depth, using: &execution)
            let session = Session(preparation: prepared.result, lifetime: lifetime)
            try execution.checkpoint()
            return session
        } catch {
            throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
        }
    }

    private func prepare(
        in bodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution
    ) throws -> Preparation {
        execution.context = execution.context.at(stage: .source)
        try tolerance.validate()
        guard let body = model.bodies[bodyID], body.kind == .sheet else {
            throw KernelError(
                phase: .classification,
                code: .missingReference,
                tolerance: tolerance,
                message: "Sheet-side classification requires a sheet body."
            )
        }
        var faceIDs: [FaceID] = []
        for shellID in body.shellIDs {
            try execution.consumeWork(1)
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Sheet classification references a missing shell.")
            }
            try execution.retainKernelValues(count: shell.faceIDs.count, stride: MemoryLayout<FaceID>.stride)
            faceIDs.append(contentsOf: shell.faceIDs)
        }
        guard faceIDs.isEmpty == false else {
            throw KernelError(
                phase: .classification,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Sheet-side classification requires at least one face."
            )
        }
        var faceBounds: [FaceID: BoundingBox3D] = [:]
        try execution.retainKernelValues(count: faceIDs.count,
            stride: MemoryLayout<(FaceID, BoundingBox3D)>.stride)
        for faceID in faceIDs {
            try execution.consumeWork(1)
            faceBounds[faceID] = try BRepFaceBoundingBoxBuilder().bounds(for: faceID,
                in: model, tolerance: tolerance, using: &execution)
        }
        let containmentSession = try crossings.facePointContainment.preparedContainmentSession(
            for: faceIDs, in: model, tolerance: tolerance, using: &execution)
        var directions: [Vector3D] = []
        for faceID in faceIDs {
            try execution.consumeWork(1)
            guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID],
                  let u = midpoint(surface.uDomain), let v = midpoint(surface.vDomain) else { continue }
            let normal = try surface.normal(u: u, v: v, tolerance: tolerance, using: &execution).normalized(tolerance: tolerance.distance)
            if directions.contains(where: { abs(abs($0.dot(normal)) - 1) <= tolerance.angle }) == false {
                try execution.retainKernelValues(count: 1, stride: MemoryLayout<Vector3D>.stride)
                directions.append(normal)
            }
        }
        for oblique in try BRepRayFaceCrossings.directions(tolerance: tolerance)
        where directions.contains(where: { abs(abs($0.dot(oblique)) - 1) <= tolerance.angle }) == false {
            try execution.consumeWork(1)
            try execution.retainKernelValues(count: 1, stride: MemoryLayout<Vector3D>.stride)
            directions.append(oblique)
        }
        return Preparation(
            crossings: crossings,
            directions: directions,
            model: model,
            faceIDs: faceIDs,
            bounds: try BRepBodyBoundingBoxBuilder().bounds(for: bodyID, in: model, tolerance: tolerance, using: &execution),
            faceBounds: faceBounds,
            containmentSession: containmentSession,
            tolerance: tolerance
        )
    }

    private func midpoint(_ domain: ParameterDomain) -> Double? {
        switch domain {
        case let .closed(lower, upper): (lower + upper) / 2
        case let .periodic(period): period / 2
        case .unbounded: 0
        }
    }

    private struct Preparation: Sendable {
        let crossings: BRepRayFaceCrossings
        let directions: [Vector3D]
        let model: BRepModel
        let faceIDs: [FaceID]
        let bounds: BoundingBox3D
        let faceBounds: [FaceID: BoundingBox3D]
        let containmentSession: (any FacePointContainmentSession)?
        let tolerance: ModelingTolerance

    }

    private final class Session: SolidPointClassificationSession {
        let preparation: Preparation
        let lifetime: PreparedBooleanQueryLifetime

        init(preparation: Preparation, lifetime: PreparedBooleanQueryLifetime) {
            self.preparation = preparation
            self.lifetime = lifetime
        }

        func classify(_ point: Point3D) throws -> SolidPointClassification {
            var execution = try lifetime.execution()
            return try classify(point, using: &execution)
        }

        func classify(_ point: Point3D, using execution: inout OriginalQueryExecution)
            throws -> SolidPointClassification {
            do {
                return try lifetime.withRead(using: &execution) { execution in
                    try classifyOriginal(point, using: &execution)
                }
            } catch {
                throw OriginalQueryFailure.published(error, context: execution.context,
                    tolerance: preparation.tolerance)
            }
        }

        private func classifyOriginal(_ point: Point3D, using execution: inout OriginalQueryExecution) throws -> SolidPointClassification {
            try point.validate()
            if try preparation.crossings.liesOnFace(
                point, faceIDs: preparation.faceIDs, faceBounds: preparation.faceBounds, model: preparation.model,
                containmentSession: preparation.containmentSession, tolerance: preparation.tolerance, using: &execution
            ) {
                return .boundary
            }
            let upperBound = preparation.crossings.upperBound(from: point, bounds: preparation.bounds, tolerance: preparation.tolerance)
            var sides: [SolidPointClassification] = []
            for direction in preparation.directions {
                try execution.consumeWork(1)
                do {
                    if let side = try side(from: point, along: direction, upperBound: upperBound, using: &execution)
                        ?? side(from: point, along: direction * -1.0, upperBound: upperBound, using: &execution) {
                        try execution.retainKernelValues(count: 1, stride: MemoryLayout<SolidPointClassification>.stride)
                        sides.append(side)
                    }
                } catch let error where OriginalQueryFailure.classification(of: error)?.code == .nonDiscreteIntersection {
                    continue
                }
            }
            guard let first = sides.first else {
                throw KernelError(
                    phase: .classification,
                    code: .classificationFailure,
                    tolerance: preparation.tolerance,
                    message: "The sheet does not reach across this point, so which side of it the point lies on is undefined."
                )
            }
            guard sides.allSatisfy({ $0 == first }) else {
                throw KernelError(
                    phase: .classification,
                    code: .classificationFailure,
                    tolerance: preparation.tolerance,
                    message: "The sheet folds back over this point, so which side of it the point lies on is ambiguous."
                )
            }
            return first
        }

        /// The side the first crossing along `direction` gives, or nil when the ray misses the
        /// sheet or grazes it.
        private func side(from point: Point3D, along direction: Vector3D, upperBound: Double, using execution: inout OriginalQueryExecution) throws -> SolidPointClassification? {
            guard let first = try preparation.crossings.crossings(
                from: point, direction: direction, upperBound: upperBound, faceIDs: preparation.faceIDs,
                model: preparation.model, containmentSession: preparation.containmentSession, tolerance: preparation.tolerance, using: &execution
            ).first else {
                return nil
            }
            guard let face = preparation.model.faces[first.faceID], let surface = preparation.model.geometry.surfaces[face.surfaceID] else {
                throw KernelError(
                    phase: .classification,
                    code: .missingReference,
                    tolerance: preparation.tolerance,
                    message: "Sheet-side classification references missing face geometry."
                )
            }
            let geometric = try surface.normal(u: first.parameter.u, v: first.parameter.v, tolerance: preparation.tolerance, using: &execution)
            let normal = face.orientation == .forward ? geometric : geometric * -1.0
            let alignment = normal.dot(direction)
            guard abs(alignment) > preparation.tolerance.angle else { return nil }
            // Leaving through the front means the point was behind the sheet.
            return alignment > 0 ? .inside : .outside
        }
    }
}
