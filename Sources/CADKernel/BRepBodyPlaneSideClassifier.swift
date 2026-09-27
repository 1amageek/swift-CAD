import CADCore
import CADGeometry
import CADModeling
import CADTopology

/// Classifies a body against a plane from enclosures of the signed distance over each face: the
/// face's bounding box, narrowed where a tighter enclosure is known. A planar face's distance is
/// affine, so it is enclosed by its boundary edges', and a B-spline patch lies in the hull of its
/// control points. Every enclosure contains the true range, so the verdict never errs toward a
/// side the body does not keep to.
struct BRepBodyPlaneSideClassifier: BodyPlaneSideClassifying {
    func side(
        of bodyID: BodyID,
        planeOrigin: Point3D,
        planeNormal: Vector3D,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BodyPlaneSide {
        try tolerance.validate()
        guard let body = model.bodies[bodyID] else {
            throw TopologyError.missingReference("Plane side classification references a missing body.")
        }
        let normal = try planeNormal.normalized(tolerance: tolerance.distance)
        func distance(_ point: Point3D) -> Double { (point - planeOrigin).dot(normal) }

        var lower = Double.infinity
        var upper = -Double.infinity
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Plane side classification references a missing shell.")
            }
            for faceID in shell.faceIDs {
                var range = try boxRange(of: faceID, model: model, tolerance: tolerance, distance: distance)
                if let narrower = try narrowerRange(of: faceID, model: model, tolerance: tolerance, normal: normal, distance: distance) {
                    range = (max(range.lower, narrower.lower), min(range.upper, narrower.upper))
                }
                lower = min(lower, range.lower)
                upper = max(upper, range.upper)
            }
        }
        guard lower.isFinite, upper.isFinite else {
            throw TopologyError.missingReference("Plane side classification needs a body with faces.")
        }
        if lower > tolerance.distance || upper < -tolerance.distance { return .clear }
        if lower >= -tolerance.distance || upper <= tolerance.distance { return .oneSided }
        return .undetermined
    }

    private func boxRange(
        of faceID: FaceID,
        model: BRepModel,
        tolerance: ModelingTolerance,
        distance: (Point3D) -> Double
    ) throws -> (lower: Double, upper: Double) {
        let box = try BRepFaceBoundingBoxBuilder().bounds(for: faceID, in: model, tolerance: tolerance)
        let low = box.minimum, high = box.maximum
        var values: [Double] = []
        for x in [low.x, high.x] {
            for y in [low.y, high.y] {
                for z in [low.z, high.z] { values.append(distance(Point3D(x: x, y: y, z: z))) }
            }
        }
        return (values.min() ?? .infinity, values.max() ?? -.infinity)
    }

    /// A tighter enclosure than the face's box, or `nil` when none is known for its geometry.
    private func narrowerRange(
        of faceID: FaceID,
        model: BRepModel,
        tolerance: ModelingTolerance,
        normal: Vector3D,
        distance: (Point3D) -> Double
    ) throws -> (lower: Double, upper: Double)? {
        guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
            throw TopologyError.missingReference("Plane side classification references a missing face.")
        }
        if case let .bSpline(patch) = surface {
            let values = patch.controlPoints.joined().map(distance)
            return (values.min() ?? .infinity, values.max() ?? -.infinity)
        }
        guard try DefaultPlanarSurfaceResolver().exactPlane(for: surface, tolerance: tolerance) != nil else {
            return nil
        }
        var lower = Double.infinity
        var upper = -Double.infinity
        for loopID in face.loops {
            guard let loop = model.loops[loopID] else {
                throw TopologyError.missingReference("Plane side classification references a missing loop.")
            }
            for coedge in loop.coedges {
                guard let range = try edgeRange(coedge.edgeID, model: model, tolerance: tolerance, normal: normal, distance: distance) else {
                    return nil
                }
                lower = min(lower, range.lower)
                upper = max(upper, range.upper)
            }
        }
        return lower.isFinite && upper.isFinite ? (lower, upper) : nil
    }

    private func edgeRange(
        _ edgeID: EdgeID,
        model: BRepModel,
        tolerance: ModelingTolerance,
        normal: Vector3D,
        distance: (Point3D) -> Double
    ) throws -> (lower: Double, upper: Double)? {
        guard let edge = model.edges[edgeID], let curve = model.geometry.curves[edge.curveID] else {
            throw TopologyError.missingReference("Plane side classification references a missing edge.")
        }
        switch curve {
        case .line:
            guard let start = model.vertices[edge.startVertexID]?.point,
                  let end = model.vertices[edge.endVertexID]?.point else {
                throw TopologyError.missingReference("Plane side classification references a missing vertex.")
            }
            let values = [distance(start), distance(end)]
            return (values.min() ?? .infinity, values.max() ?? -.infinity)
        case let .circle(circle):
            // The whole circle's extremes enclose any arc of it.
            let axis = try circle.normal.normalized(tolerance: tolerance.distance)
            let alongAxis = axis.dot(normal)
            let reach = circle.radius * (max(0, 1 - alongAxis * alongAxis)).squareRoot()
            let center = distance(circle.center)
            return (center - reach, center + reach)
        case let .bSpline(spline):
            let values = spline.controlPoints.map(distance)
            return (values.min() ?? .infinity, values.max() ?? -.infinity)
        default:
            return nil
        }
    }
}
