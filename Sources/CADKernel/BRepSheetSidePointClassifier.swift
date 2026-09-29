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

    func makeClassificationSession(
        in bodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> any SolidPointClassificationSession {
        try tolerance.validate()
        guard let body = model.bodies[bodyID], body.kind == .sheet else {
            throw KernelError(
                phase: .classification,
                code: .missingReference,
                tolerance: tolerance,
                message: "Sheet-side classification requires a sheet body."
            )
        }
        let faceIDs = body.shellIDs.flatMap { model.shells[$0]?.faceIDs ?? [] }
        guard faceIDs.isEmpty == false else {
            throw KernelError(
                phase: .classification,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Sheet-side classification requires at least one face."
            )
        }
        let faceBounds = try Dictionary(uniqueKeysWithValues: faceIDs.map {
            ($0, try BRepFaceBoundingBoxBuilder().bounds(for: $0, in: model, tolerance: tolerance))
        })
        let containmentSession = try (
            crossings.facePointContainment as? any FacePointContainmentSessionPreparing
        )?.makeContainmentSession(for: faceIDs, in: model, tolerance: tolerance)
        var directions: [Vector3D] = []
        for faceID in faceIDs {
            guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID],
                  let u = midpoint(surface.uDomain), let v = midpoint(surface.vDomain) else { continue }
            let normal = try surface.normal(u: u, v: v, tolerance: tolerance).normalized(tolerance: tolerance.distance)
            if directions.contains(where: { abs(abs($0.dot(normal)) - 1) <= tolerance.angle }) == false {
                directions.append(normal)
            }
        }
        for oblique in try BRepRayFaceCrossings.directions(tolerance: tolerance)
        where directions.contains(where: { abs(abs($0.dot(oblique)) - 1) <= tolerance.angle }) == false {
            directions.append(oblique)
        }
        return Session(
            crossings: crossings,
            directions: directions,
            model: model,
            faceIDs: faceIDs,
            bounds: try BRepBodyBoundingBoxBuilder().bounds(for: bodyID, in: model, tolerance: tolerance),
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

    private struct Session: SolidPointClassificationSession {
        let crossings: BRepRayFaceCrossings
        let directions: [Vector3D]
        let model: BRepModel
        let faceIDs: [FaceID]
        let bounds: BoundingBox3D
        let faceBounds: [FaceID: BoundingBox3D]
        let containmentSession: (any FacePointContainmentSession)?
        let tolerance: ModelingTolerance

        func classify(_ point: Point3D) throws -> SolidPointClassification {
            try point.validate()
            if try crossings.liesOnFace(
                point, faceIDs: faceIDs, faceBounds: faceBounds, model: model,
                containmentSession: containmentSession, tolerance: tolerance
            ) {
                return .boundary
            }
            let upperBound = crossings.upperBound(from: point, bounds: bounds, tolerance: tolerance)
            var sides: [SolidPointClassification] = []
            for direction in directions {
                do {
                    if let side = try side(from: point, along: direction, upperBound: upperBound)
                        ?? side(from: point, along: direction * -1.0, upperBound: upperBound) {
                        sides.append(side)
                    }
                } catch let error as KernelError where error.code == .nonDiscreteIntersection {
                    continue
                }
            }
            guard let first = sides.first else {
                throw KernelError(
                    phase: .classification,
                    code: .classificationFailure,
                    tolerance: tolerance,
                    message: "The sheet does not reach across this point, so which side of it the point lies on is undefined."
                )
            }
            guard sides.allSatisfy({ $0 == first }) else {
                throw KernelError(
                    phase: .classification,
                    code: .classificationFailure,
                    tolerance: tolerance,
                    message: "The sheet folds back over this point, so which side of it the point lies on is ambiguous."
                )
            }
            return first
        }

        /// The side the first crossing along `direction` gives, or nil when the ray misses the
        /// sheet or grazes it.
        private func side(from point: Point3D, along direction: Vector3D, upperBound: Double) throws -> SolidPointClassification? {
            guard let first = try crossings.crossings(
                from: point, direction: direction, upperBound: upperBound, faceIDs: faceIDs,
                model: model, containmentSession: containmentSession, tolerance: tolerance
            ).first else {
                return nil
            }
            guard let face = model.faces[first.faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
                throw KernelError(
                    phase: .classification,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Sheet-side classification references missing face geometry."
                )
            }
            let geometric = try surface.normal(u: first.parameter.u, v: first.parameter.v, tolerance: tolerance)
            let normal = face.orientation == .forward ? geometric : geometric * -1.0
            let alignment = normal.dot(direction)
            guard abs(alignment) > tolerance.angle else { return nil }
            // Leaving through the front means the point was behind the sheet.
            return alignment > 0 ? .inside : .outside
        }
    }
}
