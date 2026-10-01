import Foundation
import CADCore
import CADGeometry
import CADTopology

/// A round of one straight edge between two faces running along it — planes holding it, or
/// cylinders whose axes are parallel to it (an extruded outline's corner at an arc) — that ends on
/// planar faces square to it at both ends. Across the edge the problem is plane: the circle of the
/// radius tangent to the two faces' traces (lines or circles) on the corner's side — inside the
/// material at a convex corner, outside it at a concave one — found where the traces, moved the
/// radius that way, cross. The round is the exact cylinder about that circle's centre along the
/// edge; each face beside it gives up its edge for the ruling where the circle touches it, and each
/// end face takes the circle's arc across its corner.
package struct ParallelEdgeRoundBuilder {
    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// The blend across the edge: a round of the radius, or a chamfer whose contacts lie where each
    /// face offset by the distance meets the other (offset) or the distance from the edge (apex).
    package enum Section: Sendable {
        case round(Double)
        case chamfer(Double, apex: Bool)
    }

    /// A face's trace across the edge: a line through a point along a direction, or a circle.
    private enum Trace {
        case line(point: Point3D, direction: Vector3D)
        case circle(center: Point3D, radius: Double)
    }

    /// Whether `edgeID` is a straight edge between two faces running along it at least one of
    /// which is a cylinder — the edges this builder takes beyond the plane–plane blends.
    package func admits(_ edgeID: EdgeID, bodyID: BodyID, model: BRepModel) throws -> Bool {
        guard let edge = model.edges[edgeID], case .line? = model.geometry.curves[edge.curveID],
              let shell = model.bodies[bodyID]?.shellIDs.first.flatMap({ model.shells[$0] }) else { return false }
        let faces = try shell.faceIDs.filter { try uses(edgeID, face: $0, model: model) }
        guard faces.count == 2 else { return false }
        return faces.contains { faceID in
            guard let face = model.faces[faceID] else { return false }
            switch model.geometry.surfaces[face.surfaceID] {
            case .cylinder?, .analytic(.cylinder)?: return true
            default: return false
            }
        }
    }

    package func request(featureID: FeatureID, bodyID: BodyID, edgeID: EdgeID, subshapeID: SubshapeID, section: Section,
                         context: EvaluationContext) throws -> BRepSewingRequest {
        let r: Double
        switch section {
        case let .round(radius): r = radius
        case let .chamfer(distance, _): r = distance
        }
        let model = context.brep
        func refuse(_ message: String) -> KernelError {
            KernelError(phase: .evaluation, code: .unsupportedCapability, featureID: featureID, tolerance: tolerance, message: message)
        }
        guard let body = model.bodies[bodyID], body.kind == .solid, let shell = body.shellIDs.first.flatMap({ model.shells[$0] }),
              let edge = model.edges[edgeID], case .line? = model.geometry.curves[edge.curveID],
              let p0 = model.vertices[edge.startVertexID]?.point, let p1 = model.vertices[edge.endVertexID]?.point else {
            throw refuse("A round of an edge along its faces takes a straight edge of a solid.")
        }
        let length = (p1 - p0).length
        let d = try (p1 - p0).normalized(tolerance: tolerance.distance)
        let besides = try shell.faceIDs.filter { try uses(edgeID, face: $0, model: model) }
        guard besides.count == 2 else { throw refuse("A rounded edge bounds two faces.") }
        // Each face's trace across the edge in the plane through its start, and its outward normal there.
        func trace(_ faceID: FaceID) throws -> (trace: Trace, outward: Vector3D) {
            guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference("Missing face beside a rounded edge.")
            }
            let uv = try surface.parameterProjection(of: p0, tolerance: tolerance)
            let normal = try surface.normal(u: uv.u, v: uv.v, tolerance: tolerance)
            let outward = try (face.orientation == .forward ? normal : normal * -1).normalized(tolerance: tolerance.distance)
            switch surface {
            case .plane:
                guard abs(outward.dot(d)) <= tolerance.angle else { throw refuse("A rounded edge's faces run along it.") }
                return (.line(point: p0, direction: d.cross(outward)), outward)
            case let .cylinder(cylinder):
                return (try circle(origin: cylinder.origin, axis: cylinder.axis, radius: cylinder.radius, d: d, refuse), outward)
            case let .analytic(.cylinder(origin, axis, radius)):
                return (try circle(origin: origin, axis: axis, radius: radius, d: d, refuse), outward)
            default:
                throw refuse("A rounded edge runs between planes and cylinders along it.")
            }
        }
        func circle(origin: Point3D, axis: Vector3D, radius: Double, d: Vector3D, _ refuse: (String) -> KernelError) throws -> Trace {
            guard axis.cross(d).length <= tolerance.angle * max(axis.length, 1) else { throw refuse("A rounded edge's cylinders run along it.") }
            let offset = p0 - origin
            return .circle(center: p0 + (offset - d * offset.dot(d)) * -1, radius: radius)
        }
        let (a, b) = (try trace(besides[0]), try trace(besides[1]))
        // The end faces: at each end the one other face holding the vertex, a plane square to the edge.
        func endFace(_ vertexID: VertexID) throws -> FaceID {
            let holding = try shell.faceIDs.filter { faceID in
                guard besides.contains(faceID) == false, let face = model.faces[faceID] else { return false }
                return try face.loops.contains { id in
                    guard let loop = model.loops[id] else { throw TopologyError.missingReference("Missing loop.") }
                    return loop.edges.contains { use in
                        guard let other = model.edges[use.edgeID] else { return false }
                        return other.startVertexID == vertexID || other.endVertexID == vertexID
                    }
                }
            }
            guard holding.count == 1, let face = model.faces[holding[0]], case let .plane(plane)? = model.geometry.surfaces[face.surfaceID],
                  plane.normal.cross(d).length <= tolerance.angle * max(plane.normal.length, 1) else {
                throw refuse("A rounded edge ends on faces square to it.")
            }
            return holding[0]
        }
        let ends = (try endFace(edge.startVertexID), try endFace(edge.endVertexID))
        // Convex where the second face runs into the first's inside: along the second face away
        // from the edge, its trace heads below the first face.
        func intoFace(_ trace: Trace, outward: Vector3D, faceID: FaceID) throws -> Vector3D {
            let along = d.cross(outward)
            // The face lies to one side of the edge across it: toward its vertices off the edge.
            guard let face = model.faces[faceID] else { throw TopologyError.missingReference("Missing face.") }
            var points: [Point3D] = []
            for loopID in face.loops {
                for use in model.loops[loopID]?.edges ?? [] {
                    guard let other = model.edges[use.edgeID] else { continue }
                    for id in [other.startVertexID, other.endVertexID] {
                        if let point = model.vertices[id]?.point { points.append(point) }
                    }
                }
            }
            let side = points.map { offset -> Double in
                let relative = offset - p0
                return (relative - d * relative.dot(d)).dot(along)
            }.max(by: { abs($0) < abs($1) }) ?? 1
            return side >= 0 ? along : along * -1
        }
        let intoB = try intoFace(b.trace, outward: b.outward, faceID: besides[1])
        let convex = intoB.dot(a.outward) < 0
        // The traces moved the radius toward the round's centre: inward at a convex corner,
        // outward at a concave one; where they cross nearest the corner is the centre.
        let shift = convex ? -r : r
        func shifted(_ trace: Trace, outward: Vector3D) -> Trace {
            switch trace {
            case let .line(point, direction): return .line(point: point + outward * shift, direction: direction)
            case let .circle(center, radius):
                let radial = (p0 - center) * (1 / radius)
                return .circle(center: center, radius: radius + shift * outward.dot(radial))
            }
        }
        // A round touches the faces where its centre's circle does; a chamfer's contacts lie on the
        // faces where the other face's offset (or the distance's circle about the corner) crosses.
        var center = p0
        let ta: Point3D, tb: Point3D
        switch section {
        case .round:
            guard let found = try crossing(shifted(a.trace, outward: a.outward), shifted(b.trace, outward: b.outward), near: p0, d: d) else {
                throw refuse("A round of this radius does not fit between the edge's faces.")
            }
            center = found
            func touch(_ trace: Trace, outward: Vector3D) -> Point3D {
                switch trace {
                case .line: return found + outward * -shift
                case let .circle(c, radius):
                    let toward = found - c
                    return c + toward * (radius / toward.length)
                }
            }
            (ta, tb) = (touch(a.trace, outward: a.outward), touch(b.trace, outward: b.outward))
        case let .chamfer(_, apex):
            let reach = Trace.circle(center: p0, radius: r)
            let intoA = try intoFace(a.trace, outward: a.outward, faceID: besides[0])
            guard let onA = try crossing(a.trace, apex ? reach : shifted(b.trace, outward: b.outward), near: p0, d: d, toward: intoA),
                  let onB = try crossing(b.trace, apex ? reach : shifted(a.trace, outward: a.outward), near: p0, d: d, toward: intoB) else {
                throw refuse("A chamfer of this distance does not fit between the edge's faces.")
            }
            (ta, tb) = (onA, onB)
        }
        // The ruled faces the round runs between at each end, and the vertex moves.
        let lift = d * length
        let moves: [FaceID: [(from: Point3D, to: Point3D)]] = [
            besides[0]: [(p0, ta), (p1, ta + lift)],
            besides[1]: [(p0, tb), (p1, tb + lift)],
        ]
        let parents = [subshapeID]
        func line(_ start: Point3D, _ end: Point3D, _ name: String) throws -> BRepSewingEdge {
            let delta = end - start
            return BRepSewingEdge(stableID: "round:\(name)", curve: .line(Line3D(origin: start, direction: try delta.normalized(tolerance: tolerance.distance))),
                                  startParameter: 0, endParameter: delta.length, startPoint: start, endPoint: end,
                                  surfaceParameterCurve: .polyline([]), parentSubshapeIDs: parents)
        }
        let surface: Surface3D
        let cut: (Double, Point3D, Point3D, String) throws -> BRepSewingEdge
        let outward: Vector3D
        switch section {
        case .round:
            surface = .cylinder(Cylinder3D(origin: center, axis: d, radius: r))
            cut = { height, start, end, name in
                let curve = Curve3D.circle(Circle3D(center: center + d * height, normal: d, radius: r))
                let t0 = try curve.parameterProjection(of: start, tolerance: tolerance).parameter
                let t1 = nearestTurn(from: t0, to: try curve.parameterProjection(of: end, tolerance: tolerance).parameter)
                return BRepSewingEdge(stableID: "round:\(name)", curve: curve, startParameter: t0, endParameter: t1, startPoint: start,
                                      endPoint: end, surfaceParameterCurve: .polyline([]), parentSubshapeIDs: parents)
            }
            // Away from the material: from the centre at a convex corner, toward it at a concave one.
            let toward = try (ta + (tb - ta) * 0.5 - center).normalized(tolerance: tolerance.distance)
            outward = convex ? toward : toward * -1
        case .chamfer:
            let normal = try (tb - ta).cross(d).normalized(tolerance: tolerance.distance)
            // Away from the material: toward the corner it cuts off, or away from the one it fills.
            let toCorner = (p0 - ta).dot(normal) >= 0 ? normal : normal * -1
            outward = convex ? toCorner : toCorner * -1
            surface = .plane(Plane3D(origin: ta, normal: outward))
            cut = { _, start, end, name in try line(start, end, name) }
        }
        // The band: across at the start from A's ruling to B's, B's ruling up, across back, A's down.
        var band = [try cut(0, ta, tb, "start"), try line(tb, tb + lift, "second"),
                    try cut(length, tb + lift, ta + lift, "end"), try line(ta + lift, ta, "first")]
        band = try band.map { try withPcurve($0, on: surface) }
        // The band's middle: on the round's arc, or the chamfer's midpoint.
        let across = ta + (tb - ta) * 0.5
        let middle: Point3D
        switch section {
        case .round: middle = center + (try (across - center).normalized(tolerance: tolerance.distance)) * r + d * (length / 2)
        case .chamfer: middle = across + d * (length / 2)
        }
        let uv = try surface.parameterProjection(of: middle, tolerance: tolerance)
        let facing = try surface.normal(u: uv.u, v: uv.v, tolerance: tolerance).dot(outward) >= 0
        let loop = (tb - ta).cross(d).dot(outward) > 0 ? band : try band.reversed().map(reversed)
        var patches = [BRepSewingFacePatch(stableID: "round:band", surface: surface, orientation: facing ? .forward : .reversed,
                                           loops: [BRepSewingLoop(stableID: "round:band:outer", role: .outer, edges: loop)],
                                           parentSubshapeIDs: besides.flatMap { context.subshapeIDs(for: .face($0)) })]
        // Every face, the two beside the edge and its end faces edited, the rest as they were.
        for (faceIndex, faceID) in shell.faceIDs.enumerated() {
            let source = try SourceBRepFacePatchBuilder().build(faceID: faceID, stableID: "source-face:\(faceIndex)", from: model,
                                                                sourceSubshapes: context.subshapes.entries, tolerance: tolerance).patch
            if let faceMoves = moves[faceID] {
                patches.append(try moved(source, by: faceMoves, refuse))
            } else if faceID == ends.0 || faceID == ends.1 {
                let (corner, a, b) = faceID == ends.0 ? (p0, ta, tb) : (p1, ta + lift, tb + lift)
                let height = faceID == ends.0 ? 0.0 : length
                patches.append(try cornered(source, corner: corner, onA: a, onB: b, height: height, arc: cut, refuse))
            } else {
                patches.append(source)
            }
        }
        return BRepSewingRequest(featureID: featureID, bodyKind: .solid,
                                 shells: [BRepSewingShell(stableID: "shell:0", patches: patches)],
                                 bodyParentSubshapeIDs: context.subshapeIDs(for: .body(bodyID)))
    }

    /// Where two traces cross nearest `point`, in the plane across `d` through it.
    private func crossing(_ first: Trace, _ second: Trace, near point: Point3D, d: Vector3D, toward: Vector3D? = nil) throws -> Point3D? {
        let seed: Vector3D = abs(d.x) < 0.6 ? .unitX : .unitY
        let u = try d.cross(seed).normalized(tolerance: tolerance.distance)
        let v = d.cross(u)
        func flat(_ p: Point3D) -> (Double, Double) { ((p - point).dot(u), (p - point).dot(v)) }
        func flat(_ w: Vector3D) -> (Double, Double) { (w.dot(u), w.dot(v)) }
        var candidates: [(Double, Double)] = []
        switch (first, second) {
        case let (.line(p, dir), .line(q, eir)):
            let (px, py) = flat(p), (dx, dy) = flat(dir), (qx, qy) = flat(q), (ex, ey) = flat(eir)
            let determinant = dx * ey - dy * ex
            guard abs(determinant) > tolerance.angle else { return nil }
            let t = ((qx - px) * ey - (qy - py) * ex) / determinant
            candidates.append((px + dx * t, py + dy * t))
        case let (.line(p, dir), .circle(c, radius)), let (.circle(c, radius), .line(p, dir)):
            let (px, py) = flat(p), (dx, dy) = flat(dir), (cx, cy) = flat(c)
            let (fx, fy) = (px - cx, py - cy)
            let scale = dx * dx + dy * dy
            let half = (fx * dx + fy * dy) / scale
            let discriminant = half * half - (fx * fx + fy * fy - radius * radius) / scale
            guard discriminant >= 0 else { return nil }
            for t in [-half - discriminant.squareRoot(), -half + discriminant.squareRoot()] { candidates.append((px + dx * t, py + dy * t)) }
        case let (.circle(c1, r1), .circle(c2, r2)):
            let (x1, y1) = flat(c1), (x2, y2) = flat(c2)
            let (ex, ey) = (x2 - x1, y2 - y1)
            let distance = (ex * ex + ey * ey).squareRoot()
            guard distance > tolerance.distance else { return nil }
            let along = (r1 * r1 - r2 * r2 + distance * distance) / (2 * distance)
            let height = r1 * r1 - along * along
            guard height >= 0 else { return nil }
            let (mx, my) = (x1 + ex * along / distance, y1 + ey * along / distance)
            let h = height.squareRoot()
            candidates.append((mx - ey * h / distance, my + ex * h / distance))
            candidates.append((mx + ey * h / distance, my - ex * h / distance))
        }
        // A chamfer's contact lies off the corner along its face: the nearest crossing that way.
        let kept = toward.map { direction in
            candidates.filter { $0.0 * direction.dot(u) + $0.1 * direction.dot(v) > tolerance.distance }
        } ?? candidates
        guard let nearest = kept.min(by: { $0.0 * $0.0 + $0.1 * $0.1 < $1.0 * $1.0 + $1.1 * $1.1 }) else { return nil }
        return point + u * nearest.0 + v * nearest.1
    }

    /// A face beside the edge with its corners moved onto the round's rulings: its edge along the
    /// edge the ruling, the edges reaching the moved corners shortened along their own curves.
    private func moved(_ source: BRepSewingFacePatch, by moves: [(from: Point3D, to: Point3D)], _ refuse: (String) -> KernelError) throws -> BRepSewingFacePatch {
        func target(_ point: Point3D) -> Point3D? {
            moves.first { $0.from.isApproximatelyEqual(to: point, tolerance: tolerance.distance) }?.to
        }
        let loops = try source.loops.map { loop in
            BRepSewingLoop(stableID: loop.stableID, role: loop.role, edges: try loop.edges.map { edge in
                let (start, end) = (target(edge.startPoint), target(edge.endPoint))
                guard start != nil || end != nil else { return edge }
                return try rebuilt(edge, from: start ?? edge.startPoint, to: end ?? edge.endPoint, on: source.surface, refuse)
            })
        }
        return BRepSewingFacePatch(stableID: source.stableID, surface: source.surface, orientation: source.orientation, loops: loops,
                                   parentSubshapeIDs: source.parentSubshapeIDs)
    }

    /// An end face with its corner cut off by the round's arc from the point on A's side to B's.
    private func cornered(_ source: BRepSewingFacePatch, corner: Point3D, onA: Point3D, onB: Point3D, height: Double,
                          arc: (Double, Point3D, Point3D, String) throws -> BRepSewingEdge,
                          _ refuse: (String) -> KernelError) throws -> BRepSewingFacePatch {
        let loops = try source.loops.map { loop -> BRepSewingLoop in
            guard let index = loop.edges.firstIndex(where: { $0.endPoint.isApproximatelyEqual(to: corner, tolerance: tolerance.distance) }) else {
                return loop
            }
            let next = (index + 1) % loop.edges.count
            let (incoming, outgoing) = (loop.edges[index], loop.edges[next])
            // The incoming edge ends on whichever of A's and B's points lies on its curve.
            func lies(_ point: Point3D, on edge: BRepSewingEdge) throws -> Bool {
                switch edge.curve {
                case .line:
                    let direction = try (edge.endPoint - edge.startPoint).normalized(tolerance: tolerance.distance)
                    let offset = point - edge.startPoint
                    return (offset - direction * offset.dot(direction)).length <= tolerance.distance
                case let .circle(circle):
                    let normal = try circle.normal.normalized(tolerance: tolerance.distance)
                    let offset = point - circle.center
                    return abs(offset.dot(normal)) <= tolerance.distance && abs(offset.length - circle.radius) <= tolerance.distance
                default:
                    return false
                }
            }
            let (inPoint, outPoint) = try lies(onA, on: incoming) ? (onA, onB) : (onB, onA)
            guard try lies(outPoint, on: outgoing) else { throw refuse("A rounded edge's end face holds its traces beside the corner.") }
            var edges = loop.edges
            edges[index] = try rebuilt(incoming, from: incoming.startPoint, to: inPoint, on: source.surface, refuse)
            edges[next] = try rebuilt(outgoing, from: outPoint, to: outgoing.endPoint, on: source.surface, refuse)
            var cut = try arc(height, inPoint, outPoint, "cap:\(height == 0 ? "start" : "end")")
            cut = try withPcurve(cut, on: source.surface)
            edges.insert(cut, at: index + 1)
            return BRepSewingLoop(stableID: loop.stableID, role: loop.role, edges: edges)
        }
        return BRepSewingFacePatch(stableID: source.stableID, surface: source.surface, orientation: source.orientation, loops: loops,
                                   parentSubshapeIDs: source.parentSubshapeIDs)
    }

    /// `edge` run from `start` to `end` along its own line or circle, with its pcurve on `surface`.
    private func rebuilt(_ edge: BRepSewingEdge, from start: Point3D, to end: Point3D, on surface: Surface3D,
                         _ refuse: (String) -> KernelError) throws -> BRepSewingEdge {
        let delta = end - start
        guard delta.length > tolerance.distance else { throw refuse("A round removes an edge beside it.") }
        switch edge.curve {
        case .line:
            guard delta.dot(edge.endPoint - edge.startPoint) > 0 else { throw refuse("A round turns an edge beside it over.") }
            let line = BRepSewingEdge(stableID: edge.stableID, curve: .line(Line3D(origin: start, direction: try delta.normalized(tolerance: tolerance.distance))),
                                      startParameter: 0, endParameter: delta.length, startPoint: start, endPoint: end,
                                      surfaceParameterCurve: .polyline([]), parentSubshapeIDs: edge.parentSubshapeIDs,
                                      startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                                      endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs)
            return try withPcurve(line, on: surface)
        case .circle:
            // The same arc, its parameters from its new ends, turning the way it turned.
            let t0 = try edge.curve.parameterProjection(of: start, tolerance: tolerance).parameter
            var t1 = try edge.curve.parameterProjection(of: end, tolerance: tolerance).parameter
            let sense = edge.endParameter >= edge.startParameter ? 1.0 : -1.0
            while (t1 - t0) * sense <= 0 { t1 += 2 * Double.pi * sense }
            while (t1 - t0) * sense > 2 * Double.pi { t1 -= 2 * Double.pi * sense }
            let arc = BRepSewingEdge(stableID: edge.stableID, curve: edge.curve, startParameter: t0, endParameter: t1,
                                     startPoint: start, endPoint: end, surfaceParameterCurve: .polyline([]),
                                     parentSubshapeIDs: edge.parentSubshapeIDs,
                                     startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                                     endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs)
            return try withPcurve(arc, on: surface)
        default:
            throw refuse("A rounded edge's neighbours are lines and arcs.")
        }
    }

    /// `edge` with its pcurve on `surface`: on a plane a line's straight image or a circle's
    /// harmonic one; on a cylinder a ruling or a circle of constant height, turning as the curve does.
    private func withPcurve(_ edge: BRepSewingEdge, on surface: Surface3D) throws -> BRepSewingEdge {
        let pcurve: SurfaceParameterCurve
        switch (surface, edge.curve) {
        case (.plane, .circle(let circle)), (.analytic(.plane), .circle(let circle)):
            let curve = edge.curve
            let center = try surface.parameterProjection(of: circle.center, tolerance: tolerance)
            let cosine = try surface.parameterProjection(of: curve.point(at: 0, tolerance: tolerance), tolerance: tolerance)
            let sine = try surface.parameterProjection(of: curve.point(at: Double.pi / 2, tolerance: tolerance), tolerance: tolerance)
            pcurve = .harmonic(center: Point2D(x: center.u, y: center.v), cosine: Point2D(x: cosine.u - center.u, y: cosine.v - center.v),
                               sine: Point2D(x: sine.u - center.u, y: sine.v - center.v),
                               startParameter: edge.startParameter, endParameter: edge.endParameter)
        default:
            let a = try surface.parameterProjection(of: edge.startPoint, tolerance: tolerance)
            let middlePoint = try edge.curve.point(at: (edge.startParameter + edge.endParameter) / 2, tolerance: tolerance)
            let m = try surface.parameterProjection(of: middlePoint, tolerance: tolerance)
            let b = try surface.parameterProjection(of: edge.endPoint, tolerance: tolerance)
            let periodic: Bool
            switch surface {
            case .cylinder, .analytic(.cylinder): periodic = true
            default: periodic = false
            }
            let mu = periodic ? nearestTurn(from: a.u, to: m.u) : m.u
            let bu = periodic ? nearestTurn(from: mu, to: b.u) : b.u
            if abs(bu - a.u) <= tolerance.angle {
                pcurve = .constantU(u: a.u, vStart: a.v, vEnd: b.v)
            } else if abs(b.v - a.v) <= tolerance.distance {
                pcurve = .constantV(v: a.v, uStart: a.u, uEnd: bu)
            } else {
                pcurve = .polyline([SurfaceParameter(u: a.u, v: a.v), SurfaceParameter(u: bu, v: b.v)])
            }
        }
        return BRepSewingEdge(stableID: edge.stableID, curve: edge.curve, startParameter: edge.startParameter, endParameter: edge.endParameter,
                              startPoint: edge.startPoint, endPoint: edge.endPoint, surfaceParameterCurve: pcurve,
                              parentSubshapeIDs: edge.parentSubshapeIDs,
                              startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                              endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs)
    }

    private func ends(of pcurve: SurfaceParameterCurve) throws -> (SurfaceParameter, SurfaceParameter) {
        switch pcurve {
        case let .constantU(u, v0, v1): return (SurfaceParameter(u: u, v: v0), SurfaceParameter(u: u, v: v1))
        case let .constantV(v, u0, u1): return (SurfaceParameter(u: u0, v: v), SurfaceParameter(u: u1, v: v))
        case let .polyline(points) where points.count >= 2: return (points[0], points[points.count - 1])
        default: throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: tolerance, message: "A round's pcurve is straight.")
        }
    }

    private func reversed(_ edge: BRepSewingEdge) throws -> BRepSewingEdge {
        BRepSewingEdge(stableID: edge.stableID, curve: edge.curve, startParameter: edge.endParameter, endParameter: edge.startParameter,
                       startPoint: edge.endPoint, endPoint: edge.startPoint,
                       surfaceParameterCurve: try edge.surfaceParameterCurve.reversed(tolerance: tolerance),
                       parentSubshapeIDs: edge.parentSubshapeIDs,
                       startVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs,
                       endVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs)
    }

    private func uses(_ edgeID: EdgeID, face faceID: FaceID, model: BRepModel) throws -> Bool {
        guard let face = model.faces[faceID] else { throw TopologyError.missingReference("Missing face.") }
        return try face.loops.contains { loopID in
            guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("Missing loop.") }
            return loop.edges.contains { $0.edgeID == edgeID }
        }
    }

    /// `end` shifted by whole turns to lie within half a turn of `start`.
    private func nearestTurn(from start: Double, to end: Double) -> Double {
        var delta = (end - start).truncatingRemainder(dividingBy: 2 * Double.pi)
        if delta > Double.pi { delta -= 2 * Double.pi }
        if delta < -Double.pi { delta += 2 * Double.pi }
        return start + delta
    }
}
