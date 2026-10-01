import Foundation
import CADCore
import CADGeometry
import CADModeling
import CADTopology

/// The edges around a face rebuilt coarser than its edges allow, re-solved onto its new surface
/// where its neighbours are planes crossing it: each vertex where the new surface meets its two
/// neighbouring planes (Newton on the surface's parameters from the old vertex), each edge the new
/// surface's intersection with its neighbour's plane between those vertices — its trimming curve
/// on the new surface fitted through the intersection's parameters, the edge the surface along it,
/// fitted within an eighth of the distance tolerance — and each neighbour's straight edges reaching
/// a moved vertex run to it along their line, where the two planes still meet.
struct RebuiltFaceEdgeResolver {
    private let tolerance: ModelingTolerance

    init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// The patches with the face's and its neighbours' re-solved: `patches` lists every face of the
    /// shell with its patch, in the shell's order.
    func resolve(faceID: FaceID, surface: BSplineSurface3D, patches: [(faceID: FaceID, patch: BRepSewingFacePatch)],
                 model: BRepModel, featureID: FeatureID) throws -> [BRepSewingFacePatch] {
        func refuse(_ message: String) -> KernelError {
            KernelError(phase: .evaluation, code: .unsupportedCapability, featureID: featureID, tolerance: tolerance, message: message)
        }
        guard let face = model.faces[faceID] else { throw TopologyError.missingReference("A rebuilt face is missing.") }
        let new = Surface3D.bSpline(surface)
        // Each edge of the face with its neighbour's plane.
        var neighbours: [EdgeID: (faceID: FaceID, plane: Plane3D)] = [:]
        var vertexFaces: [VertexID: Set<FaceID>] = [:]
        for loopID in face.loops {
            for coedge in model.loops[loopID]?.coedges ?? [] {
                let others = model.faces.filter { otherID, other in
                    otherID != faceID && other.loops.contains { model.loops[$0]?.coedges.contains { $0.edgeID == coedge.edgeID } ?? false }
                }
                guard others.count == 1, let (otherID, other) = others.first else {
                    throw refuse("A rebuilt face's edges each bound one other face.")
                }
                guard case let .plane(plane)? = model.geometry.surfaces[other.surfaceID] else {
                    // FIXME(INCOMPLETE_IMPLEMENTATION): a face rebuilt coarser than its edges allow
                    // beside a curved neighbour needs their surfaces intersected anew, which is not
                    // built, so it is refused. Production path: FaceRebuildFeatureEvaluator through
                    // RebuiltFaceEdgeResolver. Complete only when such edges are re-solved, verified
                    // by rebuilding coarsely a face meeting a cylinder.
                    throw refuse("A face rebuilt coarser than its edges allow meets planes.")
                }
                neighbours[coedge.edgeID] = (otherID, plane)
                guard let edge = model.edges[coedge.edgeID] else { throw TopologyError.missingReference("A rebuilt face's edge is missing.") }
                for vertexID in [edge.startVertexID, edge.endVertexID] { vertexFaces[vertexID, default: []].insert(otherID) }
            }
        }
        /// The surface's position and parameter derivatives.
        func jet(_ uv: SurfaceParameter) throws -> (point: Point3D, du: Vector3D, dv: Vector3D) {
            do {
                let geometry = try new.differentialGeometry(u: uv.u, v: uv.v, tolerance: tolerance)
                return (geometry.position, geometry.tangentU, geometry.tangentV)
            } catch {
                throw refuse("A rebuilt face's edges move past its new surface; extend it.")
            }
        }
        // Each vertex where the new surface meets its two neighbouring planes.
        let oldPcurves = try pcurves(of: faceID, model: model)
        var moved: [VertexID: (point: Point3D, uv: SurfaceParameter)] = [:]
        for (vertexID, faces) in vertexFaces {
            guard faces.count == 2, let old = model.vertices[vertexID]?.point else {
                throw refuse("A rebuilt face's corners each meet two other faces.")
            }
            let planes = try faces.sorted().map { id -> Plane3D in
                guard let plane = neighbours.values.first(where: { $0.faceID == id })?.plane else {
                    throw TopologyError.missingReference("A rebuilt face's neighbour is missing.")
                }
                return plane
            }
            guard let start = oldPcurves.first(where: { $0.start.point.isApproximatelyEqual(to: old, tolerance: tolerance.distance) })?.start.uv
                    ?? oldPcurves.first(where: { $0.end.point.isApproximatelyEqual(to: old, tolerance: tolerance.distance) })?.end.uv else {
                throw TopologyError.missingReference("A rebuilt face's corner has no parameters.")
            }
            var uv = start
            for _ in 0..<64 {
                let (point, du, dv) = try jet(uv)
                let n = try planes.map { try $0.normal.normalized(tolerance: tolerance.distance) }
                let f = [n[0].dot(point - planes[0].origin), n[1].dot(point - planes[1].origin)]
                let (a, b, c, d) = (n[0].dot(du), n[0].dot(dv), n[1].dot(du), n[1].dot(dv))
                let determinant = a * d - b * c
                guard abs(determinant) > 1e-14 * max(1, du.length * dv.length) else {
                    throw refuse("A rebuilt face's new surface runs along its neighbours at a corner.")
                }
                let step = SurfaceParameter(u: -(d * f[0] - b * f[1]) / determinant, v: -(-c * f[0] + a * f[1]) / determinant)
                uv = SurfaceParameter(u: uv.u + step.u, v: uv.v + step.v)
                if abs(f[0]) + abs(f[1]) <= tolerance.distance * 1e-6 { break }
            }
            let point = try jet(uv).point
            for plane in planes where abs(try plane.normal.normalized(tolerance: tolerance.distance).dot(point - plane.origin)) > tolerance.distance / 16 {
                throw refuse("A rebuilt face's new surface does not meet its neighbours at a corner.")
            }
            moved[vertexID] = (point, uv)
        }
        // How far one step in the parameters moves on the surface, for fitting trimming curves.
        var scale = 0.0
        for pcurve in oldPcurves {
            for uv in [pcurve.start.uv, pcurve.end.uv] {
                let (_, du, dv) = try jet(uv)
                scale = max(scale, du.length, dv.length)
            }
        }
        let parameterFitter = try SpatialCurveFitter(deviation: tolerance.distance / (8 * max(scale, 1)))
        let curveFitter = try SpatialCurveFitter(deviation: tolerance.distance / 8)
        // Each edge: the new surface's crossing of its neighbour's plane between its moved ends.
        var resolved: [EdgeID: (curve: BSplineCurve3D, pcurve: BSplineCurve2D, start: Point3D, end: Point3D)] = [:]
        for old in oldPcurves {
            guard let neighbour = neighbours[old.edgeID], let edge = model.edges[old.edgeID],
                  let a = moved[old.forward ? edge.startVertexID : edge.endVertexID],
                  let b = moved[old.forward ? edge.endVertexID : edge.startVertexID] else {
                throw TopologyError.missingReference("A rebuilt face's edge lost its corners.")
            }
            let normal = try neighbour.plane.normal.normalized(tolerance: tolerance.distance)
            // Along the old trimming curve with its ends carried onto the new corners, each point
            // slid across the curve's direction onto the plane.
            let (startShift, endShift) = (SurfaceParameter(u: a.uv.u - old.start.uv.u, v: a.uv.v - old.start.uv.v),
                                          SurfaceParameter(u: b.uv.u - old.end.uv.u, v: b.uv.v - old.end.uv.v))
            func parameter(_ t: Double) throws -> SurfaceParameter {
                if t <= 0 { return a.uv }
                if t >= 1 { return b.uv }
                let base = try old.pcurve.parameter(atNormalizedFraction: t, tolerance: tolerance)
                let ahead = try old.pcurve.parameter(atNormalizedFraction: min(1, t + 1e-4), tolerance: tolerance)
                let behind = try old.pcurve.parameter(atNormalizedFraction: max(0, t - 1e-4), tolerance: tolerance)
                let tangent = (ahead.u - behind.u, ahead.v - behind.v)
                let across = (-tangent.1, tangent.0)
                var uv = SurfaceParameter(u: base.u + (1 - t) * startShift.u + t * endShift.u,
                                          v: base.v + (1 - t) * startShift.v + t * endShift.v)
                for _ in 0..<64 {
                    let (point, du, dv) = try jet(uv)
                    let f = normal.dot(point - neighbour.plane.origin)
                    if abs(f) <= tolerance.distance * 1e-6 { break }
                    let slope = normal.dot(du) * across.0 + normal.dot(dv) * across.1
                    guard abs(slope) > 1e-14 * max(1, du.length + dv.length) else {
                        // FIXME(INCOMPLETE_IMPLEMENTATION): a face rebuilt coarser than its edges
                        // allow beside a tangent neighbour has no crossing to re-solve its edge on,
                        // so it is refused. Production path: FaceRebuildFeatureEvaluator through
                        // RebuiltFaceEdgeResolver. Complete only when such edges are re-solved
                        // tangent neighbours included, verified by rebuilding a fillet face of a
                        // solid to a coarse layout.
                        throw refuse("A face rebuilt coarser than its edges allow crosses its neighbours.")
                    }
                    let s = -f / slope
                    uv = SurfaceParameter(u: uv.u + s * across.0, v: uv.v + s * across.1)
                }
                guard abs(normal.dot(try jet(uv).point - neighbour.plane.origin)) <= tolerance.distance / 16 else {
                    throw refuse("A face rebuilt coarser than its edges allow crosses its neighbours.")
                }
                return uv
            }
            let fittedParameters = try parameterFitter.fitBSpline(breakpoints: [0, 1], tolerance: tolerance) { t in
                let uv = try parameter(t)
                return Point3D(x: uv.u, y: uv.v, z: 0)
            }.curve
            let pcurve = BSplineCurve2D(degree: fittedParameters.degree, knots: fittedParameters.knots,
                                        controlPoints: fittedParameters.controlPoints.map { Point2D(x: $0.x, y: $0.y) })
            let along = { (t: Double) throws -> Point3D in
                let uv = try SurfaceParameterCurve.bSpline(pcurve).parameter(atNormalizedFraction: t, tolerance: self.tolerance)
                return try jet(uv).point
            }
            let curve = try curveFitter.fitBSpline(breakpoints: [0, 1], tolerance: tolerance, point: along).curve
            for index in 0...32 {
                let point = try curve.point(at: Double(index) / 32, tolerance: tolerance)
                guard abs(normal.dot(point - neighbour.plane.origin)) <= tolerance.distance / 4 else {
                    throw refuse("A re-solved edge strays from its neighbour's plane.")
                }
            }
            resolved[old.edgeID] = (curve, pcurve, a.point, b.point)
        }
        // The patches: the face on its new surface, its neighbours along the new edges and their
        // straight edges to the moved corners.
        let movedPoints = try moved.map { vertexID, value -> (from: Point3D, to: Point3D) in
            guard let point = model.vertices[vertexID]?.point else { throw TopologyError.missingReference("A moved corner is missing.") }
            return (point, value.point)
        }
        func movedPoint(_ point: Point3D) -> Point3D? {
            movedPoints.first { $0.from.isApproximatelyEqual(to: point, tolerance: tolerance.distance) }?.to
        }
        guard let oldSurface = model.geometry.surfaces[face.surfaceID] else { throw TopologyError.missingReference("A rebuilt face's surface is missing.") }
        let oldEnds = try oldPcurves.map { pcurve -> (edgeID: EdgeID, start: Point3D, end: Point3D, middle: Point3D) in
            let uv = try pcurve.pcurve.parameter(atNormalizedFraction: 0.5, tolerance: tolerance)
            return (pcurve.edgeID, pcurve.start.point, pcurve.end.point, try oldSurface.point(u: uv.u, v: uv.v, tolerance: tolerance))
        }
        /// The re-solved edge an old patch edge runs along (its ends and its middle), run as it
        /// runs, or nil.
        func replacement(_ edge: BRepSewingEdge, on surface: Surface3D, own: Bool) throws -> BRepSewingEdge? {
            let middle = try edge.curve.point(at: (edge.startParameter + edge.endParameter) / 2, tolerance: tolerance)
            guard let match = oldEnds.first(where: { candidate in
                ((candidate.start.isApproximatelyEqual(to: edge.startPoint, tolerance: tolerance.distance)
                    && candidate.end.isApproximatelyEqual(to: edge.endPoint, tolerance: tolerance.distance))
                    || (candidate.start.isApproximatelyEqual(to: edge.endPoint, tolerance: tolerance.distance)
                        && candidate.end.isApproximatelyEqual(to: edge.startPoint, tolerance: tolerance.distance)))
                    && (candidate.middle - middle).length <= max(tolerance.distance, 1e-3 * (candidate.end - candidate.start).length)
            }), let new = resolved[match.edgeID] else { return nil }
            let forward = match.start.isApproximatelyEqual(to: edge.startPoint, tolerance: tolerance.distance)
            let pcurve: SurfaceParameterCurve
            if own {
                pcurve = .bSpline(new.pcurve)
            } else {
                let projected = try new.curve.controlPoints.map { point -> Point2D in
                    let uv = try surface.parameterProjection(of: point, tolerance: tolerance)
                    return Point2D(x: uv.u, y: uv.v)
                }
                pcurve = .bSpline(BSplineCurve2D(degree: new.curve.degree, knots: new.curve.knots, controlPoints: projected, weights: new.curve.weights))
            }
            let (t0, t1) = forward ? (0.0, 1.0) : (1.0, 0.0)
            return BRepSewingEdge(stableID: edge.stableID, curve: .bSpline(new.curve), startParameter: t0, endParameter: t1,
                                  startPoint: forward ? new.start : new.end, endPoint: forward ? new.end : new.start,
                                  surfaceParameterCurve: forward ? pcurve : try pcurve.reversed(tolerance: tolerance),
                                  parentSubshapeIDs: edge.parentSubshapeIDs,
                                  startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                                  endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs)
        }
        let neighbourFaces = Set(neighbours.values.map(\.faceID))
        return try patches.map { entry -> BRepSewingFacePatch in
            let patch = entry.patch
            if entry.faceID == faceID {
                let loops = try patch.loops.map { loop in
                    BRepSewingLoop(stableID: loop.stableID, role: loop.role, edges: try loop.edges.map { edge in
                        guard let replaced = try replacement(edge, on: new, own: true) else {
                            throw TopologyError.missingReference("A rebuilt face's edge was not re-solved.")
                        }
                        return replaced
                    })
                }
                return BRepSewingFacePatch(stableID: patch.stableID, surface: new, orientation: patch.orientation, loops: loops,
                                           parentSubshapeIDs: patch.parentSubshapeIDs)
            }
            guard neighbourFaces.contains(entry.faceID) else { return patch }
            let loops = try patch.loops.map { loop in
                BRepSewingLoop(stableID: loop.stableID, role: loop.role, edges: try loop.edges.map { edge in
                    if let replaced = try replacement(edge, on: patch.surface, own: false) { return replaced }
                    let (start, end) = (movedPoint(edge.startPoint), movedPoint(edge.endPoint))
                    guard start != nil || end != nil else { return edge }
                    guard case .line = edge.curve else {
                        throw refuse("A rebuilt face's neighbours reach its corners along straight edges.")
                    }
                    let (p, q) = (start ?? edge.startPoint, end ?? edge.endPoint)
                    let delta = q - p
                    guard delta.dot(edge.endPoint - edge.startPoint) > tolerance.distance * delta.length else {
                        throw refuse("A rebuilt face's new corners pass the ends of its neighbours' edges.")
                    }
                    let (pa, pb) = (try patch.surface.parameterProjection(of: p, tolerance: tolerance),
                                    try patch.surface.parameterProjection(of: q, tolerance: tolerance))
                    return BRepSewingEdge(stableID: edge.stableID,
                                          curve: .line(Line3D(origin: p, direction: try delta.normalized(tolerance: tolerance.distance))),
                                          startParameter: 0, endParameter: delta.length, startPoint: p, endPoint: q,
                                          surfaceParameterCurve: .polyline([SurfaceParameter(u: pa.u, v: pa.v), SurfaceParameter(u: pb.u, v: pb.v)]),
                                          parentSubshapeIDs: edge.parentSubshapeIDs,
                                          startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                                          endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs)
                })
            }
            return BRepSewingFacePatch(stableID: patch.stableID, surface: patch.surface, orientation: patch.orientation, loops: loops,
                                       parentSubshapeIDs: patch.parentSubshapeIDs)
        }
    }

    /// The face's coedges with their trimming curves on its old surface, run as the loops run them,
    /// and their ends' points and parameters.
    private func pcurves(of faceID: FaceID, model: BRepModel) throws
        -> [(edgeID: EdgeID, forward: Bool, pcurve: SurfaceParameterCurve,
             start: (point: Point3D, uv: SurfaceParameter), end: (point: Point3D, uv: SurfaceParameter))] {
        guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
            throw TopologyError.missingReference("A rebuilt face is missing.")
        }
        return try face.loops.flatMap { loopID in
            try (model.loops[loopID]?.coedges ?? []).map { coedge in
                guard let pcurve = coedge.surfaceParameterCurve, let edge = model.edges[coedge.edgeID],
                      let a = model.vertices[edge.startVertexID]?.point, let b = model.vertices[edge.endVertexID]?.point else {
                    throw TopologyError.missingReference("A rebuilt face's edge has no trimming curve.")
                }
                let (startUV, endUV) = (try pcurve.parameter(atNormalizedFraction: 0, tolerance: tolerance),
                                        try pcurve.parameter(atNormalizedFraction: 1, tolerance: tolerance))
                // Whether the trimming curve runs from the edge's start to its end.
                let first = try surface.point(u: startUV.u, v: startUV.v, tolerance: tolerance)
                let forward = (first - a).length <= (first - b).length
                return (coedge.edgeID, forward, pcurve, (forward ? a : b, startUV), (forward ? b : a, endUV))
            }
        }
    }
}
