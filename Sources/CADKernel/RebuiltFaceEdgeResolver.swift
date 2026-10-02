import Foundation
import CADCore
import CADGeometry
import CADModeling
import CADTopology

/// The edges around a face rebuilt coarser than its edges allow, re-solved onto its new surface
/// where its neighbours cross it (planes, cylinders and spheres measured in closed form, any other
/// surface by the foot of a point on it): each corner where the new
/// surface meets its two neighbours (Newton on the surface's parameters from the old corner, on the
/// neighbours' signed distances), each edge the new surface's crossing of its neighbour between those
/// corners — its trimming curve on the new surface fitted through the crossing's parameters, the edge
/// the surface along it, fitted within an eighth of the distance tolerance — and each neighbour's
/// edges reaching a moved corner run to it along their own curve, where the two neighbours still meet.
struct RebuiltFaceEdgeResolver {
    private let tolerance: ModelingTolerance

    init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// A neighbour as its signed distance: zero on it, its gradient a unit normal. Planes,
    /// cylinders and spheres in closed form; any other surface by the foot of the point on it,
    /// Newton on (S − p)·S_u = (S − p)·S_v = 0 from the parameters of a point of it nearby.
    private enum Neighbour {
        case plane(origin: Point3D, normal: Vector3D)
        case cylinder(origin: Point3D, axis: Vector3D, radius: Double)
        case sphere(center: Point3D, radius: Double)
        case surface(Surface3D)

        /// The signed distance of `point` and its gradient; `seed` is a point of the neighbour
        /// near `point`, where a general surface's foot is sought from.
        func measure(_ point: Point3D, seed: Point3D, tolerance: ModelingTolerance) throws -> (distance: Double, gradient: Vector3D) {
            switch self {
            case let .plane(origin, normal): return (normal.dot(point - origin), normal)
            case let .cylinder(origin, axis, radius):
                let offset = point - origin
                let radial = offset - axis * offset.dot(axis)
                return (radial.length - radius, try radial.normalized(tolerance: tolerance.distance))
            case let .sphere(center, radius):
                return ((point - center).length - radius, try (point - center).normalized(tolerance: tolerance.distance))
            case let .surface(surface):
                let start = try surface.parameterProjection(of: seed, tolerance: tolerance)
                var (u, v) = (start.u, start.v)
                var jet = try surface.differentialGeometry(u: u, v: v, tolerance: tolerance)
                for _ in 0..<32 {
                    let r = jet.position - point
                    let (fu, fv) = (r.dot(jet.tangentU), r.dot(jet.tangentV))
                    let a = jet.tangentU.dot(jet.tangentU) + r.dot(jet.secondDerivativeUU)
                    let b = jet.tangentU.dot(jet.tangentV) + r.dot(jet.secondDerivativeUV)
                    let d = jet.tangentV.dot(jet.tangentV) + r.dot(jet.secondDerivativeVV)
                    let determinant = a * d - b * b
                    guard determinant > 0 else { break }
                    let (du, dv) = ((d * fu - b * fv) / determinant, (a * fv - b * fu) / determinant)
                    (u, v) = (u - du, v - dv)
                    jet = try surface.differentialGeometry(u: u, v: v, tolerance: tolerance)
                    if abs(du) * jet.tangentU.length + abs(dv) * jet.tangentV.length <= tolerance.distance * 1e-9 { break }
                }
                // The foot: the offset from it runs along the normal.
                let offset = point - jet.position
                guard (offset - jet.normal * offset.dot(jet.normal)).length <= max(tolerance.distance * 1e-3, 1e-3 * offset.length) else {
                    throw KernelError(phase: .geometry, code: .classificationFailure, tolerance: tolerance,
                                      message: "A point's foot on a rebuilt face's neighbour did not converge.")
                }
                return (offset.dot(jet.normal), jet.normal)
            }
        }
    }

    /// The patches with the face's and its neighbours' re-solved: `patches` lists every face of the
    /// shell with its patch, in the shell's order.
    func resolve(faceID: FaceID, surface: BSplineSurface3D, patches: [(faceID: FaceID, patch: BRepSewingFacePatch)],
                 model: BRepModel, featureID: FeatureID) throws -> [BRepSewingFacePatch] {
        func refuse(_ message: String) -> KernelError {
            KernelError(phase: .evaluation, code: .unsupportedCapability, featureID: featureID, tolerance: tolerance, message: message)
        }
        guard let face = model.faces[faceID], let oldSurface = model.geometry.surfaces[face.surfaceID] else {
            throw TopologyError.missingReference("A rebuilt face is missing.")
        }
        let new = Surface3D.bSpline(surface)
        // Each edge of the face with its neighbour.
        var neighbours: [EdgeID: (faceID: FaceID, neighbour: Neighbour)] = [:]
        var vertexFaces: [VertexID: Set<FaceID>] = [:]
        for loopID in face.loops {
            for coedge in model.loops[loopID]?.coedges ?? [] {
                let others = model.faces.filter { otherID, other in
                    otherID != faceID && other.loops.contains { model.loops[$0]?.coedges.contains { $0.edgeID == coedge.edgeID } ?? false }
                }
                guard others.count == 1, let (otherID, other) = others.first else {
                    throw refuse("A rebuilt face's edges each bound one other face.")
                }
                let neighbour: Neighbour
                switch model.geometry.surfaces[other.surfaceID] {
                case let .plane(plane)?:
                    neighbour = .plane(origin: plane.origin, normal: try plane.normal.normalized(tolerance: tolerance.distance))
                case let .cylinder(cylinder)?:
                    neighbour = .cylinder(origin: cylinder.origin, axis: try cylinder.axis.normalized(tolerance: tolerance.distance),
                                          radius: cylinder.radius)
                case let .analytic(.cylinder(origin, axis, radius))?:
                    neighbour = .cylinder(origin: origin, axis: try axis.normalized(tolerance: tolerance.distance), radius: radius)
                case let .analytic(.sphere(center, radius))?:
                    neighbour = .sphere(center: center, radius: radius)
                case let surface?:
                    neighbour = .surface(surface)
                case nil:
                    throw TopologyError.missingReference("A rebuilt face's neighbour has no surface.")
                }
                neighbours[coedge.edgeID] = (otherID, neighbour)
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
        // Each corner where the new surface meets its two neighbours.
        let oldPcurves = try pcurves(of: faceID, model: model)
        var moved: [VertexID: (point: Point3D, uv: SurfaceParameter)] = [:]
        for (vertexID, faces) in vertexFaces {
            guard faces.count == 2, let old = model.vertices[vertexID]?.point else {
                throw refuse("A rebuilt face's corners each meet two other faces.")
            }
            let pair = try faces.sorted().map { id -> Neighbour in
                guard let neighbour = neighbours.values.first(where: { $0.faceID == id })?.neighbour else {
                    throw TopologyError.missingReference("A rebuilt face's neighbour is missing.")
                }
                return neighbour
            }
            guard let start = oldPcurves.first(where: { $0.start.point.isApproximatelyEqual(to: old, tolerance: tolerance.distance) })?.start.uv
                    ?? oldPcurves.first(where: { $0.end.point.isApproximatelyEqual(to: old, tolerance: tolerance.distance) })?.end.uv else {
                throw TopologyError.missingReference("A rebuilt face's corner has no parameters.")
            }
            var uv = start
            for _ in 0..<64 {
                let (point, du, dv) = try jet(uv)
                let measured = try pair.map { try $0.measure(point, seed: old, tolerance: tolerance) }
                let f = measured.map(\.distance)
                if abs(f[0]) + abs(f[1]) <= tolerance.distance * 1e-6 { break }
                let g = measured.map(\.gradient)
                let (a, b, c, d) = (g[0].dot(du), g[0].dot(dv), g[1].dot(du), g[1].dot(dv))
                let determinant = a * d - b * c
                guard abs(determinant) > 1e-14 * max(1, du.length * dv.length) else {
                    throw refuse("A rebuilt face's new surface runs along its neighbours at a corner.")
                }
                uv = SurfaceParameter(u: uv.u - (d * f[0] - b * f[1]) / determinant, v: uv.v - (-c * f[0] + a * f[1]) / determinant)
            }
            let point = try jet(uv).point
            guard try pair.allSatisfy({ abs(try $0.measure(point, seed: old, tolerance: tolerance).distance) <= tolerance.distance / 16 }) else {
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
        // Each edge: the new surface's crossing of its neighbour between its moved ends.
        var resolved: [EdgeID: (curve: BSplineCurve3D, pcurve: BSplineCurve2D, start: Point3D, end: Point3D)] = [:]
        // Edges the new surface still runs through, ends and all (a bilinear refit keeps the
        // straight edges between its corners): kept as they are, only given trimming curves on it.
        var kept: Set<EdgeID> = []
        for old in oldPcurves {
            guard let neighbour = neighbours[old.edgeID]?.neighbour, let edge = model.edges[old.edgeID],
                  let a = moved[old.forward ? edge.startVertexID : edge.endVertexID],
                  let b = moved[old.forward ? edge.endVertexID : edge.startVertexID] else {
                throw TopologyError.missingReference("A rebuilt face's edge lost its corners.")
            }
            if a.point.isApproximatelyEqual(to: old.start.point, tolerance: tolerance.distance / 16),
               b.point.isApproximatelyEqual(to: old.end.point, tolerance: tolerance.distance / 16) {
                let onNew = try (0...16).allSatisfy { index in
                    let uv = try old.pcurve.parameter(atNormalizedFraction: Double(index) / 16, tolerance: tolerance)
                    let point = try oldSurface.point(u: uv.u, v: uv.v, tolerance: tolerance)
                    guard case let .projected(projection) = try new.parameterProjectionResult(of: point, tolerance: tolerance) else { return false }
                    return projection.residual <= tolerance.distance / 8
                }
                if onNew {
                    kept.insert(old.edgeID)
                    continue
                }
            }
            // Along the old trimming curve with its ends carried onto the new corners, each point
            // slid across the curve's direction onto the neighbour.
            let (startShift, endShift) = (SurfaceParameter(u: a.uv.u - old.start.uv.u, v: a.uv.v - old.start.uv.v),
                                          SurfaceParameter(u: b.uv.u - old.end.uv.u, v: b.uv.v - old.end.uv.v))
            func parameter(_ t: Double) throws -> SurfaceParameter {
                if t <= 0 { return a.uv }
                if t >= 1 { return b.uv }
                let base = try old.pcurve.parameter(atNormalizedFraction: t, tolerance: tolerance)
                let ahead = try old.pcurve.parameter(atNormalizedFraction: min(1, t + 1e-4), tolerance: tolerance)
                let behind = try old.pcurve.parameter(atNormalizedFraction: max(0, t - 1e-4), tolerance: tolerance)
                let across = (-(ahead.v - behind.v), ahead.u - behind.u)
                var uv = SurfaceParameter(u: base.u + (1 - t) * startShift.u + t * endShift.u,
                                          v: base.v + (1 - t) * startShift.v + t * endShift.v)
                // The old edge's point there lies on the neighbour: where its foot is sought from.
                let seed = try oldSurface.point(u: base.u, v: base.v, tolerance: tolerance)
                for _ in 0..<64 {
                    let (point, du, dv) = try jet(uv)
                    let (f, g) = try neighbour.measure(point, seed: seed, tolerance: tolerance)
                    if abs(f) <= tolerance.distance * 1e-6 { break }
                    let slope = g.dot(du) * across.0 + g.dot(dv) * across.1
                    guard abs(slope) > 1e-14 * max(1, du.length + dv.length) else {
                        // FIXME(INCOMPLETE_IMPLEMENTATION): a new surface that strays from an edge
                        // while touching its neighbour there without crossing it (a refit kept
                        // tangent to the faces beside a round) has no crossing to re-solve the edge
                        // on, so it is refused. Production path: FaceRebuildFeatureEvaluator through
                        // RebuiltFaceEdgeResolver. Complete only when such edges are re-solved,
                        // verified by a round refitted coarsely but tangent to its neighbours.
                        throw refuse("A face rebuilt coarser than its edges allow crosses its neighbours.")
                    }
                    let s = -f / slope
                    uv = SurfaceParameter(u: uv.u + s * across.0, v: uv.v + s * across.1)
                }
                guard abs(try neighbour.measure(try jet(uv).point, seed: seed, tolerance: tolerance).distance) <= tolerance.distance / 16 else {
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
                let oldUV = try old.pcurve.parameter(atNormalizedFraction: Double(index) / 32, tolerance: tolerance)
                let seed = try oldSurface.point(u: oldUV.u, v: oldUV.v, tolerance: tolerance)
                guard abs(try neighbour.measure(point, seed: seed, tolerance: tolerance).distance) <= tolerance.distance / 4 else {
                    throw refuse("A re-solved edge strays from its neighbour.")
                }
            }
            resolved[old.edgeID] = (curve, pcurve, a.point, b.point)
        }
        // The patches: the face on its new surface, its neighbours along the new edges and their
        // edges to the moved corners.
        let movedPoints = try moved.map { vertexID, value -> (from: Point3D, to: Point3D) in
            guard let point = model.vertices[vertexID]?.point else { throw TopologyError.missingReference("A moved corner is missing.") }
            return (point, value.point)
        }
        func movedPoint(_ point: Point3D) -> Point3D? {
            movedPoints.first { $0.from.isApproximatelyEqual(to: point, tolerance: tolerance.distance) }?.to
        }
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
            }) else { return nil }
            if kept.contains(match.edgeID) {
                // A kept edge: the neighbours' as it was, the face's on its new surface.
                guard own else { return nil }
                return BRepSewingEdge(stableID: edge.stableID, curve: edge.curve, startParameter: edge.startParameter,
                                      endParameter: edge.endParameter, startPoint: edge.startPoint, endPoint: edge.endPoint,
                                      surfaceParameterCurve: try fittedPcurve(edge.curve, from: edge.startParameter, to: edge.endParameter, on: surface),
                                      parentSubshapeIDs: edge.parentSubshapeIDs,
                                      startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                                      endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs)
            }
            guard let new = resolved[match.edgeID] else { return nil }
            let forward = match.start.isApproximatelyEqual(to: edge.startPoint, tolerance: tolerance.distance)
            let curve = Curve3D.bSpline(new.curve)
            let pcurve: SurfaceParameterCurve = own ? .bSpline(new.pcurve) : try fittedPcurve(curve, from: 0, to: 1, on: surface)
            let (t0, t1) = forward ? (0.0, 1.0) : (1.0, 0.0)
            return BRepSewingEdge(stableID: edge.stableID, curve: curve, startParameter: t0, endParameter: t1,
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
                    return try movedEdge(edge, start: start ?? edge.startPoint, end: end ?? edge.endPoint, on: patch.surface, refuse)
                })
            }
            return BRepSewingFacePatch(stableID: patch.stableID, surface: patch.surface, orientation: patch.orientation, loops: loops,
                                       parentSubshapeIDs: patch.parentSubshapeIDs)
        }
    }

    /// A neighbour's edge run to its moved ends along its own line, circle or curve, with its
    /// trimming curve on the neighbour.
    private func movedEdge(_ edge: BRepSewingEdge, start p: Point3D, end q: Point3D, on surface: Surface3D,
                           _ refuse: (String) -> KernelError) throws -> BRepSewingEdge {
        let curve: Curve3D
        let (t0, t1): (Double, Double)
        // Where the new ends fall along the old edge, as fractions of it.
        let fractions: (Double, Double)
        switch edge.curve {
        case .line:
            let (a, b) = (try edge.curve.parameterProjection(of: p, tolerance: tolerance).parameter,
                          try edge.curve.parameterProjection(of: q, tolerance: tolerance).parameter)
            fractions = ((a - edge.startParameter) / (edge.endParameter - edge.startParameter),
                         (b - edge.startParameter) / (edge.endParameter - edge.startParameter))
            let delta = q - p
            guard delta.dot(edge.endPoint - edge.startPoint) > tolerance.distance * delta.length else {
                throw refuse("A rebuilt face's new corners pass the ends of its neighbours' edges.")
            }
            curve = .line(Line3D(origin: p, direction: try delta.normalized(tolerance: tolerance.distance)))
            (t0, t1) = (0, delta.length)
        case .circle:
            // The same circle, each end's parameter the turn nearest its old one.
            curve = edge.curve
            func near(_ point: Point3D, _ old: Double) throws -> Double {
                let raw = try curve.parameterProjection(of: point, tolerance: tolerance).parameter
                var delta = (raw - old).truncatingRemainder(dividingBy: 2 * Double.pi)
                if delta > Double.pi { delta -= 2 * Double.pi }
                if delta < -Double.pi { delta += 2 * Double.pi }
                return old + delta
            }
            (t0, t1) = (try near(p, edge.startParameter), try near(q, edge.endParameter))
            guard (t1 - t0) * (edge.endParameter - edge.startParameter) > 0 else {
                throw refuse("A rebuilt face's new corners pass the ends of its neighbours' edges.")
            }
            fractions = ((t0 - edge.startParameter) / (edge.endParameter - edge.startParameter),
                         (t1 - edge.startParameter) / (edge.endParameter - edge.startParameter))
        default:
            // Any other curve: the moved corners lie on it (they are on both faces it divides),
            // so it is trimmed anew at their parameters — a B-spline cut exactly to that piece.
            let (a, b) = (try edge.curve.parameterProjection(of: p, tolerance: tolerance).parameter,
                          try edge.curve.parameterProjection(of: q, tolerance: tolerance).parameter)
            guard (b - a) * (edge.endParameter - edge.startParameter) > 0 else {
                throw refuse("A rebuilt face's new corners pass the ends of its neighbours' edges.")
            }
            if case let .bSpline(spline) = edge.curve {
                curve = .bSpline(try BSplineCurveSegmentExtractor().segment(of: spline, from: min(a, b), to: max(a, b), tolerance: tolerance))
            } else {
                curve = edge.curve
            }
            (t0, t1) = (a, b)
            fractions = ((a - edge.startParameter) / (edge.endParameter - edge.startParameter),
                         (b - edge.startParameter) / (edge.endParameter - edge.startParameter))
        }
        let pcurve: SurfaceParameterCurve
        if let trimmed = try trimmedPcurve(edge.surfaceParameterCurve, from: fractions.0, to: fractions.1) {
            // The old trimming curve, exact, cut to the new ends.
            pcurve = trimmed
        } else if case .line = curve, case .plane = surface {
            let (a, b) = (try surface.parameterProjection(of: p, tolerance: tolerance), try surface.parameterProjection(of: q, tolerance: tolerance))
            pcurve = .polyline([SurfaceParameter(u: a.u, v: a.v), SurfaceParameter(u: b.u, v: b.v)])
        } else {
            pcurve = try fittedPcurve(curve, from: t0, to: t1, on: surface)
        }
        return BRepSewingEdge(stableID: edge.stableID, curve: curve, startParameter: t0, endParameter: t1, startPoint: p, endPoint: q,
                              surfaceParameterCurve: pcurve, parentSubshapeIDs: edge.parentSubshapeIDs,
                              startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                              endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs)
    }

    /// `pcurve` cut to the fractions `f0` to `f1` of it, for the kinds that cut exactly (iso-lines,
    /// segments and B-splines); nil for others. The fraction runs with the edge's own parameter,
    /// as the trimming curves of exact edges do.
    private func trimmedPcurve(_ pcurve: SurfaceParameterCurve, from f0: Double, to f1: Double) throws -> SurfaceParameterCurve? {
        func along(_ a: Double, _ b: Double, _ f: Double) -> Double { a + (b - a) * f }
        switch pcurve {
        case let .constantU(u, vStart, vEnd):
            return .constantU(u: u, vStart: along(vStart, vEnd, f0), vEnd: along(vStart, vEnd, f1))
        case let .constantV(v, uStart, uEnd):
            return .constantV(v: v, uStart: along(uStart, uEnd, f0), uEnd: along(uStart, uEnd, f1))
        case let .polyline(points) where points.count == 2:
            return .polyline([SurfaceParameter(u: along(points[0].u, points[1].u, f0), v: along(points[0].v, points[1].v, f0)),
                              SurfaceParameter(u: along(points[0].u, points[1].u, f1), v: along(points[0].v, points[1].v, f1))])
        case let .bSpline(spline):
            guard let first = spline.knots.first, let last = spline.knots.last else { return nil }
            let lifted = BSplineCurve3D(degree: spline.degree, knots: spline.knots,
                                        controlPoints: spline.controlPoints.map { Point3D(x: $0.x, y: $0.y, z: 0) }, weights: spline.weights)
            let (a, b) = (along(first, last, f0), along(first, last, f1))
            let piece = try BSplineCurveSegmentExtractor().segment(of: lifted, from: min(a, b), to: max(a, b), tolerance: tolerance)
            let cut = SurfaceParameterCurve.bSpline(BSplineCurve2D(degree: piece.degree, knots: piece.knots,
                                                                   controlPoints: piece.controlPoints.map { Point2D(x: $0.x, y: $0.y) },
                                                                   weights: piece.weights))
            return a < b ? cut : try cut.reversed(tolerance: tolerance)
        default:
            return nil
        }
    }

    /// `curve` from `t0` to `t1` as a trimming curve on `surface`: on a plane its control points'
    /// image for a spline (exact, the plane's parameters being affine), otherwise its points'
    /// parameters fitted within an eighth of the distance tolerance, a periodic parameter carried
    /// on from the curve's middle.
    private func fittedPcurve(_ curve: Curve3D, from t0: Double, to t1: Double, on surface: Surface3D) throws -> SurfaceParameterCurve {
        if case .plane = surface, case let .bSpline(spline) = curve,
           Set([t0, t1]) == Set([spline.knots.first, spline.knots.last].compactMap { $0 }) {
            let projected = try spline.controlPoints.map { point -> Point2D in
                let uv = try surface.parameterProjection(of: point, tolerance: tolerance)
                return Point2D(x: uv.u, y: uv.v)
            }
            let pcurve = SurfaceParameterCurve.bSpline(BSplineCurve2D(degree: spline.degree, knots: spline.knots,
                                                                      controlPoints: projected, weights: spline.weights))
            return t0 < t1 ? pcurve : try pcurve.reversed(tolerance: tolerance)
        }
        let uPeriod: Double?
        switch surface {
        case .cylinder, .analytic(.cylinder), .analytic(.sphere): uPeriod = 2 * Double.pi
        default: uPeriod = nil
        }
        let reference = try surface.parameterProjection(of: try curve.point(at: (t0 + t1) / 2, tolerance: tolerance), tolerance: tolerance)
        // A parameter step moves a point at most this far on the surface.
        let samples = try [0.0, 0.5, 1.0].map { fraction -> Double in
            let uv = try surface.parameterProjection(of: try curve.point(at: t0 + (t1 - t0) * fraction, tolerance: tolerance), tolerance: tolerance)
            let geometry = try surface.differentialGeometry(u: uv.u, v: uv.v, tolerance: tolerance)
            return max(geometry.tangentU.length, geometry.tangentV.length)
        }
        let fitter = try SpatialCurveFitter(deviation: tolerance.distance / (8 * max(samples.max() ?? 1, 1)))
        let fitted = try fitter.fitBSpline(breakpoints: [0, 1], tolerance: tolerance) { fraction in
            let uv = try surface.parameterProjection(of: try curve.point(at: t0 + (t1 - t0) * fraction, tolerance: tolerance), tolerance: tolerance)
            var u = uv.u
            if let period = uPeriod {
                u = reference.u + (u - reference.u - period * ((u - reference.u) / period).rounded())
            }
            return Point3D(x: u, y: uv.v, z: 0)
        }.curve
        return .bSpline(BSplineCurve2D(degree: fitted.degree, knots: fitted.knots, controlPoints: fitted.controlPoints.map { Point2D(x: $0.x, y: $0.y) }))
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
