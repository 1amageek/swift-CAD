import Foundation
import CADCore
import CADGeometry
import CADModeling
import CADTopology

/// The edges around faces rebuilt coarser than their edges allow, re-solved onto their new
/// surfaces where their neighbours cross them (planes, cylinders and spheres measured in closed
/// form, any other surface — a rebuilt neighbour's new one among them — by the foot of a point on
/// it): each corner where the surfaces of its three faces meet (Newton on a rebuilt face's
/// parameters from the old corner, on the other two's signed distances), each edge a rebuilt
/// face's new surface's crossing of the face across between those corners (two rebuilt faces'
/// shared edge solved once, on the first's parameters) — its trimming curve on the new surface fitted through the crossing's parameters, the edge
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
        /// A neighbour rebuilt with this face: its new surface and the old one it was refitted on.
        case rebuilt(Surface3D, old: Surface3D)

        /// Where a general or rebuilt neighbour's foot is sought from: the parameters of a point of
        /// it (of its old surface, for a rebuilt one) near the points measured; none for the
        /// closed forms.
        struct Start {
            let uv: (u: Double, v: Double)?
        }

        /// The start near `seed`, a point of the neighbour (of its old surface, for a rebuilt one),
        /// found once for every point measured from it.
        func start(near seed: Point3D, tolerance: ModelingTolerance) throws -> Start {
            switch self {
            case .plane, .cylinder, .sphere:
                return Start(uv: nil)
            case let .surface(surface), let .rebuilt(_, surface):
                let projection = try surface.parameterProjection(of: seed, tolerance: tolerance)
                return Start(uv: (projection.u, projection.v))
            }
        }

        /// The signed distance of `point` and its gradient, a general surface's foot sought from
        /// `start`.
        func measure(_ point: Point3D, from start: Start, tolerance: ModelingTolerance) throws -> (distance: Double, gradient: Vector3D) {
            switch self {
            case let .plane(origin, normal): return (normal.dot(point - origin), normal)
            case let .cylinder(origin, axis, radius):
                let offset = point - origin
                let radial = offset - axis * offset.dot(axis)
                return (radial.length - radius, try radial.normalized(tolerance: tolerance.distance))
            case let .sphere(center, radius):
                return ((point - center).length - radius, try (point - center).normalized(tolerance: tolerance.distance))
            case let .surface(surface), let .rebuilt(surface, _):
                guard let uv = start.uv else {
                    throw TopologyError.missingReference("A neighbour's foot has no start.")
                }
                let foot = try Self.foot(of: point, on: surface, from: (uv.u, uv.v), tolerance: tolerance)
                return (foot.distance, foot.gradient)
            }
        }

        /// A rebuilt neighbour's foot of `point` with its parameters: the new spline is refitted on
        /// the old surface's parameters, so a start there starts the foot on the new one.
        func rebuiltFoot(of point: Point3D, from start: Start, tolerance: ModelingTolerance)
            throws -> (distance: Double, gradient: Vector3D, uv: SurfaceParameter) {
            guard case let .rebuilt(surface, _) = self, let uv = start.uv else {
                throw TopologyError.missingReference("A foot's parameters are sought on a neighbour not rebuilt.")
            }
            return try Self.foot(of: point, on: surface, from: (uv.u, uv.v), tolerance: tolerance)
        }

        /// The signed distance of `point` from `surface`, its normal there and the foot's
        /// parameters, by the foot of the point: Newton on (S − p)·S_u = (S − p)·S_v = 0 from `start`.
        private static func foot(of point: Point3D, on surface: Surface3D, from start: (Double, Double),
                                 tolerance: ModelingTolerance) throws -> (distance: Double, gradient: Vector3D, uv: SurfaceParameter) {
            var (u, v) = start
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
            return (offset.dot(jet.normal), jet.normal, SurfaceParameter(u: u, v: v))
        }
    }

    /// The patches with the rebuilt faces' and their neighbours' edges re-solved together:
    /// `surfaces` holds each face rebuilt coarser than its edges allow with its new surface, and
    /// `patches` every face of the shell with its patch, in the shell's order. An edge two rebuilt
    /// faces share is their new surfaces' crossing, solved on the first's parameters; a corner is
    /// where the surfaces of its three faces meet, new for the rebuilt ones.
    func resolve(surfaces: [FaceID: BSplineSurface3D], patches: [(faceID: FaceID, patch: BRepSewingFacePatch)],
                 model: BRepModel, featureID: FeatureID) throws -> [BRepSewingFacePatch] {
        func refuse(_ message: String) -> KernelError {
            KernelError(phase: .evaluation, code: .unsupportedCapability, featureID: featureID, tolerance: tolerance, message: message)
        }
        let rebuilt = surfaces.keys.sorted()
        /// A face's surface as a neighbour: its new one when it is rebuilt.
        func neighbour(_ faceID: FaceID) throws -> Neighbour {
            guard let other = model.faces[faceID] else { throw TopologyError.missingReference("A rebuilt face's neighbour is missing.") }
            if let fitted = surfaces[faceID] {
                guard let old = model.geometry.surfaces[other.surfaceID] else {
                    throw TopologyError.missingReference("A rebuilt face's neighbour has no surface.")
                }
                return .rebuilt(.bSpline(fitted), old: old)
            }
            switch model.geometry.surfaces[other.surfaceID] {
            case let .plane(plane)?:
                return .plane(origin: plane.origin, normal: try plane.normal.normalized(tolerance: tolerance.distance))
            case let .cylinder(cylinder)?:
                return .cylinder(origin: cylinder.origin, axis: try cylinder.axis.normalized(tolerance: tolerance.distance),
                                 radius: cylinder.radius)
            case let .analytic(.cylinder(origin, axis, radius))?:
                return .cylinder(origin: origin, axis: try axis.normalized(tolerance: tolerance.distance), radius: radius)
            case let .analytic(.sphere(center, radius))?:
                return .sphere(center: center, radius: radius)
            case let surface?:
                return .surface(surface)
            case nil:
                throw TopologyError.missingReference("A rebuilt face's neighbour has no surface.")
            }
        }
        /// The faces bounded by an edge.
        func faces(of edgeID: EdgeID) -> [FaceID] {
            model.faces.keys.filter { faceID in
                model.faces[faceID]?.loops.contains { model.loops[$0]?.coedges.contains { $0.edgeID == edgeID } ?? false } ?? false
            }.sorted()
        }
        /// A rebuilt face's new surface's position and parameter derivatives.
        func jet(_ uv: SurfaceParameter, on faceID: FaceID) throws -> (point: Point3D, du: Vector3D, dv: Vector3D) {
            guard let fitted = surfaces[faceID] else { throw TopologyError.missingReference("A rebuilt face lost its surface.") }
            do {
                let geometry = try Surface3D.bSpline(fitted).differentialGeometry(u: uv.u, v: uv.v, tolerance: tolerance)
                return (geometry.position, geometry.tangentU, geometry.tangentV)
            } catch {
                // Sought where the new surface cannot be evaluated: it does not reach the face
                // beside the edge there (short of it, or a coarse refit of a face tangent to its
                // neighbours hovering off them).
                throw refuse("A rebuilt face's new surface does not reach the face beside one of its edges; rebuild it finer or extend it.")
            }
        }
        func oldSurface(_ faceID: FaceID) throws -> Surface3D {
            guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference("A rebuilt face is missing.")
            }
            return surface
        }
        var oldPcurves: [FaceID: [(edgeID: EdgeID, forward: Bool, pcurve: SurfaceParameterCurve,
                                   start: (point: Point3D, uv: SurfaceParameter), end: (point: Point3D, uv: SurfaceParameter))]] = [:]
        for faceID in rebuilt { oldPcurves[faceID] = try pcurves(of: faceID, model: model) }
        // Each edge of a rebuilt face: the face it is solved on (the first rebuilt face it bounds)
        // and the face across it.
        var edgeHosts: [EdgeID: (host: FaceID, other: FaceID)] = [:]
        var vertexFaces: [VertexID: Set<FaceID>] = [:]
        for faceID in rebuilt {
            for old in oldPcurves[faceID] ?? [] {
                let bounded = faces(of: old.edgeID)
                guard bounded.count == 2, bounded.contains(faceID), let other = bounded.first(where: { $0 != faceID }) else {
                    throw refuse("A rebuilt face's edges each bound one other face.")
                }
                if edgeHosts[old.edgeID] == nil { edgeHosts[old.edgeID] = (faceID, other) }
                guard let edge = model.edges[old.edgeID] else { throw TopologyError.missingReference("A rebuilt face's edge is missing.") }
                for vertexID in [edge.startVertexID, edge.endVertexID] { vertexFaces[vertexID, default: []].formUnion(bounded) }
            }
        }
        // Each corner where the surfaces of its three faces meet, solved on a rebuilt face's
        // parameters against the other two.
        var moved: [VertexID: Point3D] = [:]
        var cornerUV: [VertexID: [FaceID: SurfaceParameter]] = [:]
        for (vertexID, around) in vertexFaces.sorted(by: { $0.key < $1.key }) {
            guard around.count == 3, let old = model.vertices[vertexID]?.point,
                  let host = around.sorted().first(where: { surfaces[$0] != nil }) else {
                throw refuse("A rebuilt face's corners each meet two other faces.")
            }
            let pair = try around.sorted().filter { $0 != host }.map(neighbour)
            guard let start = oldPcurves[host]?.first(where: { $0.start.point.isApproximatelyEqual(to: old, tolerance: tolerance.distance) })?.start.uv
                    ?? oldPcurves[host]?.first(where: { $0.end.point.isApproximatelyEqual(to: old, tolerance: tolerance.distance) })?.end.uv else {
                throw TopologyError.missingReference("A rebuilt face's corner has no parameters.")
            }
            let starts = try pair.map { try $0.start(near: old, tolerance: tolerance) }
            var uv = start
            for _ in 0..<64 {
                let (point, du, dv) = try jet(uv, on: host)
                let measured = try zip(pair, starts).map { try $0.measure(point, from: $1, tolerance: tolerance) }
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
            let point = try jet(uv, on: host).point
            guard try zip(pair, starts).allSatisfy({ abs(try $0.measure(point, from: $1, tolerance: tolerance).distance) <= tolerance.distance / 16 }) else {
                throw refuse("A rebuilt face's new surface does not meet its neighbours at a corner.")
            }
            moved[vertexID] = point
            cornerUV[vertexID, default: [:]][host] = uv
            // The corner's parameters on every other rebuilt face around it, for its edges there.
            for other in around where other != host && surfaces[other] != nil {
                guard case let .projected(projection) = try Surface3D.bSpline(surfaces[other]!).parameterProjectionResult(of: point, tolerance: tolerance),
                      projection.residual <= tolerance.distance / 16 else {
                    throw refuse("A rebuilt face's new surface does not meet its neighbours at a corner.")
                }
                cornerUV[vertexID, default: [:]][other] = SurfaceParameter(u: projection.u, v: projection.v)
            }
        }
        // Each edge: the host's new surface's crossing of the face across between its moved ends.
        var resolved: [EdgeID: (curve: BSplineCurve3D, pcurve: BSplineCurve2D, host: FaceID, start: Point3D, end: Point3D)] = [:]
        // A shared edge's trimming curve on the rebuilt face across from its host.
        var acrossPcurves: [EdgeID: BSplineCurve2D] = [:]
        // Edges the new surfaces still run through, ends and all (a bilinear refit keeps the
        // straight edges between its corners): kept as they are, only given trimming curves on them.
        var kept: Set<EdgeID> = []
        for (edgeID, sides) in edgeHosts.sorted(by: { $0.key < $1.key }) {
            let host = sides.host
            guard let old = oldPcurves[host]?.first(where: { $0.edgeID == edgeID }), let edge = model.edges[edgeID] else {
                throw TopologyError.missingReference("A rebuilt face's edge lost its trimming curve.")
            }
            let (startVertex, endVertex) = old.forward ? (edge.startVertexID, edge.endVertexID) : (edge.endVertexID, edge.startVertexID)
            guard let aPoint = moved[startVertex], let bPoint = moved[endVertex],
                  let aUV = cornerUV[startVertex]?[host], let bUV = cornerUV[endVertex]?[host] else {
                throw TopologyError.missingReference("A rebuilt face's edge lost its corners.")
            }
            let across = try neighbour(sides.other)
            let hostOld = try oldSurface(host)
            if aPoint.isApproximatelyEqual(to: old.start.point, tolerance: tolerance.distance / 16),
               bPoint.isApproximatelyEqual(to: old.end.point, tolerance: tolerance.distance / 16) {
                let onNew = try (0...16).allSatisfy { index in
                    let uv = try old.pcurve.parameter(atNormalizedFraction: Double(index) / 16, tolerance: tolerance)
                    let point = try hostOld.point(u: uv.u, v: uv.v, tolerance: tolerance)
                    return try [host, sides.other].compactMap { surfaces[$0] }.allSatisfy { fitted in
                        guard case let .projected(projection) = try Surface3D.bSpline(fitted).parameterProjectionResult(of: point, tolerance: tolerance) else {
                            return false
                        }
                        return projection.residual <= tolerance.distance / 8
                    }
                }
                if onNew {
                    kept.insert(edgeID)
                    continue
                }
            }
            // Along the old trimming curve with its ends carried onto the new corners, each point
            // slid across the curve's direction onto the face across.
            let (startShift, endShift) = (SurfaceParameter(u: aUV.u - old.start.uv.u, v: aUV.v - old.start.uv.v),
                                          SurfaceParameter(u: bUV.u - old.end.uv.u, v: bUV.v - old.end.uv.v))
            func parameter(_ t: Double) throws -> SurfaceParameter {
                if t <= 0 { return aUV }
                if t >= 1 { return bUV }
                let base = try old.pcurve.parameter(atNormalizedFraction: t, tolerance: tolerance)
                let ahead = try old.pcurve.parameter(atNormalizedFraction: min(1, t + 1e-4), tolerance: tolerance)
                let behind = try old.pcurve.parameter(atNormalizedFraction: max(0, t - 1e-4), tolerance: tolerance)
                let direction = (-(ahead.v - behind.v), ahead.u - behind.u)
                var uv = SurfaceParameter(u: base.u + (1 - t) * startShift.u + t * endShift.u,
                                          v: base.v + (1 - t) * startShift.v + t * endShift.v)
                // The old edge's point there lies on the face across: where its foot is sought from.
                let seed = try across.start(near: try hostOld.point(u: base.u, v: base.v, tolerance: tolerance), tolerance: tolerance)
                for _ in 0..<64 {
                    let (point, du, dv) = try jet(uv, on: host)
                    let (f, g) = try across.measure(point, from: seed, tolerance: tolerance)
                    if abs(f) <= tolerance.distance * 1e-6 { break }
                    let slope = g.dot(du) * direction.0 + g.dot(dv) * direction.1
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
                    uv = SurfaceParameter(u: uv.u + s * direction.0, v: uv.v + s * direction.1)
                }
                guard abs(try across.measure(try jet(uv, on: host).point, from: seed, tolerance: tolerance).distance) <= tolerance.distance / 16 else {
                    throw refuse("A face rebuilt coarser than its edges allow crosses its neighbours.")
                }
                return uv
            }
            // How far one step in the parameters moves on the surface, for fitting trimming curves.
            var scale = 0.0
            for uv in [aUV, bUV, old.start.uv, old.end.uv] {
                let (_, du, dv) = try jet(uv, on: host)
                scale = max(scale, du.length, dv.length)
            }
            let parameterFitter = try SpatialCurveFitter(deviation: tolerance.distance / (8 * max(scale, 1)))
            let curveFitter = try SpatialCurveFitter(deviation: tolerance.distance / 8)
            let fittedParameters = try parameterFitter.fitBSpline(breakpoints: [0, 1], tolerance: tolerance) { t in
                let uv = try parameter(t)
                return Point3D(x: uv.u, y: uv.v, z: 0)
            }.curve
            let pcurve = BSplineCurve2D(degree: fittedParameters.degree, knots: fittedParameters.knots,
                                        controlPoints: fittedParameters.controlPoints.map { Point2D(x: $0.x, y: $0.y) })
            let along = { (t: Double) throws -> Point3D in
                let uv = try SurfaceParameterCurve.bSpline(pcurve).parameter(atNormalizedFraction: t, tolerance: self.tolerance)
                return try jet(uv, on: host).point
            }
            let curve = try curveFitter.fitBSpline(breakpoints: [0, 1], tolerance: tolerance, point: along).curve
            for index in 0...32 {
                let point = try curve.point(at: Double(index) / 32, tolerance: tolerance)
                let oldUV = try old.pcurve.parameter(atNormalizedFraction: Double(index) / 32, tolerance: tolerance)
                let seed = try across.start(near: try hostOld.point(u: oldUV.u, v: oldUV.v, tolerance: tolerance), tolerance: tolerance)
                guard abs(try across.measure(point, from: seed, tolerance: tolerance).distance) <= tolerance.distance / 4 else {
                    throw refuse("A re-solved edge strays from its neighbour.")
                }
            }
            resolved[edgeID] = (curve, pcurve, host, aPoint, bPoint)
            if case .rebuilt(let acrossSurface, _) = across {
                // On the rebuilt face across: each point's foot there, from its old parameters.
                var acrossScale = 0.0
                for vertexID in [startVertex, endVertex] {
                    guard let uv = cornerUV[vertexID]?[sides.other] else { continue }
                    let geometry = try acrossSurface.differentialGeometry(u: uv.u, v: uv.v, tolerance: tolerance)
                    acrossScale = max(acrossScale, geometry.tangentU.length, geometry.tangentV.length)
                }
                let acrossFitter = try SpatialCurveFitter(deviation: tolerance.distance / (8 * max(acrossScale, 1)))
                let fitted = try acrossFitter.fitBSpline(breakpoints: [0, 1], tolerance: tolerance) { t in
                    let point = try along(t)
                    let oldUV = try old.pcurve.parameter(atNormalizedFraction: min(1, max(0, t)), tolerance: tolerance)
                    let seed = try across.start(near: try hostOld.point(u: oldUV.u, v: oldUV.v, tolerance: tolerance), tolerance: tolerance)
                    let uv = try across.rebuiltFoot(of: point, from: seed, tolerance: tolerance).uv
                    return Point3D(x: uv.u, y: uv.v, z: 0)
                }.curve
                acrossPcurves[edgeID] = BSplineCurve2D(degree: fitted.degree, knots: fitted.knots,
                                                       controlPoints: fitted.controlPoints.map { Point2D(x: $0.x, y: $0.y) })
            }
        }
        // The patches: the rebuilt faces on their new surfaces, their neighbours along the new
        // edges and their edges to the moved corners.
        let movedPoints = try moved.map { vertexID, point -> (from: Point3D, to: Point3D) in
            guard let old = model.vertices[vertexID]?.point else { throw TopologyError.missingReference("A moved corner is missing.") }
            return (old, point)
        }
        func movedPoint(_ point: Point3D) -> Point3D? {
            movedPoints.first { $0.from.isApproximatelyEqual(to: point, tolerance: tolerance.distance) }?.to
        }
        var oldEnds: [(edgeID: EdgeID, start: Point3D, end: Point3D, middle: Point3D)] = []
        for (edgeID, sides) in edgeHosts {
            guard let old = oldPcurves[sides.host]?.first(where: { $0.edgeID == edgeID }) else { continue }
            let uv = try old.pcurve.parameter(atNormalizedFraction: 0.5, tolerance: tolerance)
            oldEnds.append((edgeID, old.start.point, old.end.point, try oldSurface(sides.host).point(u: uv.u, v: uv.v, tolerance: tolerance)))
        }
        /// The re-solved edge an old patch edge runs along (its ends and its middle), run as it
        /// runs, with its trimming curve on `surface` (the host's own when `faceID` hosts it), or nil.
        func replacement(_ edge: BRepSewingEdge, of faceID: FaceID, on surface: Surface3D) throws -> BRepSewingEdge? {
            let middle = try edge.curve.point(at: (edge.startParameter + edge.endParameter) / 2, tolerance: tolerance)
            guard let match = oldEnds.first(where: { candidate in
                ((candidate.start.isApproximatelyEqual(to: edge.startPoint, tolerance: tolerance.distance)
                    && candidate.end.isApproximatelyEqual(to: edge.endPoint, tolerance: tolerance.distance))
                    || (candidate.start.isApproximatelyEqual(to: edge.endPoint, tolerance: tolerance.distance)
                        && candidate.end.isApproximatelyEqual(to: edge.startPoint, tolerance: tolerance.distance)))
                    && (candidate.middle - middle).length <= max(tolerance.distance, 1e-3 * (candidate.end - candidate.start).length)
            }) else { return nil }
            if kept.contains(match.edgeID) {
                // A kept edge: an old neighbour's as it was, a rebuilt face's on its new surface.
                guard surfaces[faceID] != nil else { return nil }
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
            let pcurve: SurfaceParameterCurve
            if new.host == faceID {
                pcurve = .bSpline(new.pcurve)
            } else if let across = acrossPcurves[match.edgeID], surfaces[faceID] != nil {
                pcurve = .bSpline(across)
            } else {
                pcurve = try fittedPcurve(curve, from: 0, to: 1, on: surface)
            }
            let (t0, t1) = forward ? (0.0, 1.0) : (1.0, 0.0)
            return BRepSewingEdge(stableID: edge.stableID, curve: curve, startParameter: t0, endParameter: t1,
                                  startPoint: forward ? new.start : new.end, endPoint: forward ? new.end : new.start,
                                  surfaceParameterCurve: forward ? pcurve : try pcurve.reversed(tolerance: tolerance),
                                  parentSubshapeIDs: edge.parentSubshapeIDs,
                                  startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                                  endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs)
        }
        let touched = Set(edgeHosts.values.flatMap { [$0.host, $0.other] }).union(vertexFaces.values.flatMap { $0 })
        return try patches.map { entry -> BRepSewingFacePatch in
            let patch = entry.patch
            if let fitted = surfaces[entry.faceID] {
                let new = Surface3D.bSpline(fitted)
                let loops = try patch.loops.map { loop in
                    BRepSewingLoop(stableID: loop.stableID, role: loop.role, edges: try loop.edges.map { edge in
                        guard let replaced = try replacement(edge, of: entry.faceID, on: new) else {
                            throw TopologyError.missingReference("A rebuilt face's edge was not re-solved.")
                        }
                        return replaced
                    })
                }
                return BRepSewingFacePatch(stableID: patch.stableID, surface: new, orientation: patch.orientation, loops: loops,
                                           parentSubshapeIDs: patch.parentSubshapeIDs)
            }
            guard touched.contains(entry.faceID) else { return patch }
            let loops = try patch.loops.map { loop in
                BRepSewingLoop(stableID: loop.stableID, role: loop.role, edges: try loop.edges.map { edge in
                    if let replaced = try replacement(edge, of: entry.faceID, on: patch.surface) { return replaced }
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
