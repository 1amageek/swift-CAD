import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Where a ray crosses a set of faces transversally, inside their trims: the shared ray cast of
/// point-in-solid and sheet-side classification.
struct BRepRayFaceCrossings: Sendable {
    struct Crossing: Sendable {
        let point: Point3D
        let faceID: FaceID
        /// Distance along the ray.
        let distance: Double
        let parameter: SurfaceParameter
        /// The face's outward normal there.
        let normal: Vector3D
    }

    let intersector: any CurveSurfaceIntersecting
    let facePointContainment: any FacePointContainmentTesting

    /// The distinct transverse crossings of the ray from `point` along the unit `direction`
    /// between twice the modeling distance and `upperBound`, nearest first.
    func crossings(
        from point: Point3D,
        direction: Vector3D,
        upperBound: Double,
        faceIDs: [FaceID],
        model: BRepModel,
        containmentSession: (any FacePointContainmentSession)?,
        tolerance: ModelingTolerance
    ) throws -> [Crossing] {
        let ray = Curve3D.line(Line3D(origin: point, direction: direction))
        let range = try ScalarInterval(lower: tolerance.distance * 2.0, upper: upperBound)
        var crossings: [Crossing] = []
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
                let parameter = SurfaceParameter(u: intersection.surfaceU, v: intersection.surfaceV)
                guard try contains(
                    parameter,
                    fallbackPoint: intersection.point,
                    on: faceID,
                    model: model,
                    containmentSession: containmentSession,
                    tolerance: tolerance
                ) else {
                    continue
                }
                // A ray through an edge meets both faces it bounds at one point: one crossing.
                // Two faces lying on each other with opposite normals (solids touching along a
                // face) are two crossings at one point: out of one and into the other.
                let normal = try orientedNormal(of: face, surface: surface, at: parameter, tolerance: tolerance)
                let isRepeat = try crossings.contains { existing in
                    guard (existing.point - intersection.point).length <= tolerance.distance else { return false }
                    return existing.normal.dot(normal) > -1 + tolerance.angle
                }
                if isRepeat == false {
                    crossings.append(Crossing(
                        point: intersection.point,
                        faceID: faceID,
                        distance: intersection.curveParameter,
                        parameter: parameter,
                        normal: normal
                    ))
                }
            }
        }
        return crossings.sorted { $0.distance < $1.distance }
    }

    private func orientedNormal(
        of face: Face,
        surface: Surface3D,
        at parameter: SurfaceParameter,
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        let geometric = try surface.normal(u: parameter.u, v: parameter.v, tolerance: tolerance)
            .normalized(tolerance: tolerance.distance)
        return face.orientation == .forward ? geometric : geometric * -1.0
    }

    /// Whether `point` lies on one of the faces.
    func liesOnFace(
        _ point: Point3D,
        faceIDs: [FaceID],
        faceBounds: [FaceID: BoundingBox3D],
        model: BRepModel,
        containmentSession: (any FacePointContainmentSession)?,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        for faceID in faceIDs {
            if let bounds = faceBounds[faceID], bounds.contains(point, tolerance: tolerance.distance) == false {
                continue
            }
            do {
                let contained: Bool
                if let containmentSession {
                    contained = try containmentSession.contains(point, on: faceID)
                } else {
                    contained = try facePointContainment.contains(point, on: faceID, in: model, tolerance: tolerance)
                }
                if contained { return true }
            } catch let error as KernelError where error.code == .intersectionFailure {
                continue
            } catch GeometryError.invalidVectorLength {
                continue
            }
        }
        return false
    }

    /// Twice the largest distance from `point` to a corner of `bounds`: a ray this long leaves them.
    func upperBound(from point: Point3D, bounds: BoundingBox3D, tolerance: ModelingTolerance) -> Double {
        let corners = [bounds.minimum.x, bounds.maximum.x].flatMap { x in
            [bounds.minimum.y, bounds.maximum.y].flatMap { y in
                [bounds.minimum.z, bounds.maximum.z].map { z in Point3D(x: x, y: y, z: z) }
            }
        }
        let maximumDistance = corners.map { ($0 - point).length }.max() ?? 0.0
        return max(maximumDistance * 2.0, tolerance.distance * 16.0)
    }

    /// The three fixed, mutually oblique ray directions classification casts along.
    static func directions(tolerance: ModelingTolerance) throws -> [Vector3D] {
        try [
            Vector3D(x: 1.0, y: 0.371_390_676_354, z: 0.618_033_988_750),
            Vector3D(x: 0.414_213_562_373, y: 1.0, z: 0.732_050_807_569),
            Vector3D(x: 0.577_215_664_902, y: 0.693_147_180_560, z: 1.0),
        ].map { try $0.normalized(tolerance: tolerance.distance) }
    }

    private func contains(
        _ parameter: SurfaceParameter,
        fallbackPoint: Point3D,
        on faceID: FaceID,
        model: BRepModel,
        containmentSession: (any FacePointContainmentSession)?,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        if let parameterSession = containmentSession as? any FaceParameterContainmentSession {
            return try parameterSession.contains(parameter, on: faceID)
        }
        if let containmentSession {
            return try containmentSession.contains(fallbackPoint, on: faceID)
        }
        return try facePointContainment.contains(fallbackPoint, on: faceID, in: model, tolerance: tolerance)
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
}
