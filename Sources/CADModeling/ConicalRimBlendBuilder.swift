import Foundation
import CADCore
import CADGeometry
import CADTopology

/// A round or chamfer all the way round a circular rim between a planar cap and a coaxial cone:
/// a cone's base, a frustum's top or bottom, a cone standing in a hole of a plate. The rim is a
/// closed loop of arcs of one circle on the cap; each arc's other face is the cone, leaving the
/// cap at the same angle all round. In the half plane through the axis (the meridian) the cap and
/// the cone's generator are two lines meeting at the rim at an angle `α`; the round's circle of
/// the radius touches both, `r / tan(α/2)` from the rim along each, and turned about the axis it
/// is a torus. A chamfer's line between its contacts turned about the axis is a cone (a cylinder
/// when both contacts lie at one radius). The cap's loop shrinks or grows to the cap contact, the
/// cone's rim moves down its generators to the wall contact, and the cone's straight seams are
/// shortened to meet it. The band is one patch per rim arc, meeting the next on the section.
package struct ConicalRimBlendBuilder {
    private let tolerance: ModelingTolerance
    private let followsTangents: Bool

    package init(tolerance: ModelingTolerance, followsTangents: Bool = true) {
        self.tolerance = tolerance
        self.followsTangents = followsTangents
    }

    /// The band's section: a round of the radius, or a chamfer whose distances along the cap and
    /// along the cone follow from the angle between them.
    package enum Section {
        case round(Double)
        case chamfer((_ angle: Double) throws -> (cap: Double, wall: Double))
    }

    /// A rim: its cap and loop, the circle's centre and radius, the cap's outward normal, the
    /// meridian directions along the cap (`capSide`, +1 away from the axis) and down the cone's
    /// generator (`wall`, as radial and normal components), and its cone.
    private struct Rim {
        let capFaceIDs: Set<FaceID>
        let center: Point3D
        let radius: Double
        let normal: Vector3D
        let capSide: Double
        let wall: (radial: Double, normal: Double)
        let arcEdgeIDs: [EdgeID]
        let wallFaceIDs: Set<FaceID>
    }

    /// Whether the edges are arcs of one circular rim between a planar cap and a coaxial cone.
    package func admits(_ edgeIDs: [EdgeID], model: BRepModel) throws -> Bool {
        try rim(of: edgeIDs, model: model) != nil
    }

    package func request(featureID: FeatureID, bodyID: BodyID, selected: [(edgeID: EdgeID, subshapeID: SubshapeID)],
                         section: Section, context: EvaluationContext) throws -> BRepSewingRequest {
        let model = context.brep
        func refuse(_ message: String) -> KernelError {
            KernelError(phase: .evaluation, code: .unsupportedCapability, featureID: featureID, tolerance: tolerance, message: message)
        }
        guard let rim = try rim(of: selected.map(\.edgeID), model: model) else {
            throw refuse("A conical rim's blend takes arcs of one circle between a planar cap and a coaxial cone.")
        }
        guard let body = model.bodies[bodyID], body.kind == .solid, body.shellIDs.count == 1,
              let shell = model.shells[body.shellIDs[0]], rim.capFaceIDs.union(rim.wallFaceIDs).isSubset(of: Set(shell.faceIDs)) else {
            throw refuse("A conical rim is blended on one single-shell solid.")
        }
        if followsTangents == false, Set(selected.map(\.edgeID)) != Set(rim.arcEdgeIDs) {
            // FIXME(INCOMPLETE_IMPLEMENTATION): part of a conical rim blended with Tangent Edges
            // off closes its band on the section at each end, which is not built, so it is
            // refused. Production path: ConicalRimBlendBuilder from Fillet and Chamfer. Complete
            // only when such ends close, verified by a cone's base arc rounded alone.
            throw refuse("A conical rim's blend runs all the way round its rim.")
        }
        // The meridian: along the cap from the rim, and down the cone's generator.
        let (capRadial, wallRadial, wallNormal) = (rim.capSide, rim.wall.radial, rim.wall.normal)
        let angle = acos(max(-1, min(1, capRadial * wallRadial)))
        guard angle > tolerance.angle, angle < Double.pi - tolerance.angle else {
            throw refuse("A conical rim's cap and cone meet at a corner.")
        }
        // The contacts' meridian offsets from the rim, and the round's centre.
        let capContact: Double
        let wallContact: Double
        let roundCenter: (radial: Double, normal: Double)?
        switch section {
        case let .round(radius):
            let along = radius / tan(angle / 2)
            (capContact, wallContact) = (along, along)
            let bisector = (radial: capRadial + wallRadial, normal: wallNormal)
            let length = (bisector.radial * bisector.radial + bisector.normal * bisector.normal).squareRoot()
            let reach = radius / sin(angle / 2)
            roundCenter = (bisector.radial / length * reach, bisector.normal / length * reach)
        case let .chamfer(distances):
            (capContact, wallContact) = try distances(angle)
            roundCenter = nil
        }
        let capRadius = rim.radius + capRadial * capContact
        let wallRadius = rim.radius + wallRadial * wallContact
        let wallDrop = wallNormal * wallContact
        guard capRadius > tolerance.distance, wallRadius > tolerance.distance else {
            throw refuse("A conical rim's blend is larger than its cap or its cone.")
        }
        if let roundCenter, case let .round(radius) = section, rim.radius + roundCenter.radial <= radius + tolerance.distance {
            throw refuse("A conical rim's round is wider than its distance from the axis.")
        }
        try checkCapClear(rim, capRadius: capRadius, model: model, refuse: refuse)

        let n = rim.normal
        func radial(_ point: Point3D) throws -> Vector3D {
            let offset = point - rim.center
            return try (offset - n * offset.dot(n)).normalized(tolerance: tolerance.distance)
        }
        func onCap(_ point: Point3D) throws -> Point3D { rim.center + (try radial(point)) * capRadius }
        func onWall(_ point: Point3D) throws -> Point3D { rim.center + n * wallDrop + (try radial(point)) * wallRadius }
        let parents = selected.map(\.subshapeID)
        let faceParents = (rim.capFaceIDs.sorted() + rim.wallFaceIDs.sorted()).flatMap { context.subshapeIDs(for: .face($0)) }
        // The band's surface about the axis.
        let band: Surface3D
        if let roundCenter, case let .round(radius) = section {
            band = .analytic(.torus(center: rim.center + n * roundCenter.normal, axis: n,
                                    majorRadius: rim.radius + roundCenter.radial, minorRadius: radius))
        } else if abs(capRadius - wallRadius) <= tolerance.distance {
            band = .analytic(.cylinder(origin: rim.center, axis: n, radius: capRadius))
        } else {
            // The chamfer's line from the cap contact to the wall contact meets the axis at the apex.
            let reachAxis = capRadius / (capRadius - wallRadius)
            let apex = rim.center + n * (wallDrop * reachAxis)
            let axis = n * ((wallDrop * reachAxis) <= wallDrop / 2 ? 1 : -1)
            let halfAngle = atan(abs(capRadius - wallRadius) / abs(wallDrop))
            band = .analytic(.cone(apex: apex, axis: axis, halfAngle: halfAngle))
        }
        /// The section at a rim point: from the cap contact to the wall contact.
        func sectionEdge(at point: Point3D, _ stableID: String, upward: Bool = false) throws -> BRepSewingEdge {
            let (p, q) = upward ? (try onWall(point), try onCap(point)) : (try onCap(point), try onWall(point))
            if let roundCenter, case let .round(radius) = section {
                let e = try radial(point)
                let circle = Circle3D(center: rim.center + e * (rim.radius + roundCenter.radial) + n * roundCenter.normal,
                                      normal: try n.cross(e).normalized(tolerance: tolerance.distance), radius: radius)
                let curve = Curve3D.circle(circle)
                let t0 = try curve.parameterProjection(of: p, tolerance: tolerance).parameter
                let t1 = try curve.parameterProjection(of: q, tolerance: tolerance).parameter
                // The arc facing the rim, less than half a turn.
                return BRepSewingEdge(stableID: stableID, curve: curve, startParameter: t0, endParameter: t0 + remainder(t1 - t0, 2 * Double.pi),
                                      startPoint: p, endPoint: q, surfaceParameterCurve: .polyline([]), parentSubshapeIDs: parents)
            }
            let delta = q - p
            return BRepSewingEdge(stableID: stableID, curve: .line(Line3D(origin: p, direction: try delta.normalized(tolerance: tolerance.distance))),
                                  startParameter: 0, endParameter: delta.length, startPoint: p, endPoint: q,
                                  surfaceParameterCurve: .polyline([]), parentSubshapeIDs: parents)
        }
        var patches: [BRepSewingFacePatch] = []
        // One band patch per rim arc, from the cap contact round to the wall contact.
        for (index, edgeID) in rim.arcEdgeIDs.enumerated() {
            let (start, middle, end) = try arcPoints(edgeID, model: model)
            let stableID = "conical-rim:\(index)"
            let capArc = try arc(from: try onCap(start), through: try onCap(middle), to: try onCap(end),
                                 on: Circle3D(center: rim.center, normal: n, radius: capRadius), "\(stableID):cap", parents)
            let wallArc = try arc(from: try onWall(end), through: try onWall(middle), to: try onWall(start),
                                  on: Circle3D(center: rim.center + n * wallDrop, normal: n, radius: wallRadius), "\(stableID):wall", parents)
            let edges = [capArc, try sectionEdge(at: end, "\(stableID):end"), wallArc,
                         try sectionEdge(at: start, "\(stableID):start", upward: true)]
            patches.append(try bandPatch(stableID, edges: edges, on: band, reference: try onCap(middle),
                                         outward: try outward(at: middle, rim: rim, section: section, roundCenter: roundCenter,
                                                              capContact: capContact, wallContact: wallContact),
                                         across: try onWall(middle) - (try onCap(middle)), parents: faceParents))
        }
        // The cap's rim moved to the cap contact, the cone's to the wall contact, its seams
        // shortened to meet it; every other face as it was.
        func isRim(_ edge: BRepSewingEdge) -> Bool {
            guard let circle = circleOf(edge.curve) else { return false }
            return circle.center.isApproximatelyEqual(to: rim.center, tolerance: tolerance.distance)
                && abs(circle.radius - rim.radius) <= tolerance.distance
        }
        func onRim(_ point: Point3D) -> Bool {
            let offset = point - rim.center
            return abs(offset.dot(n)) <= tolerance.distance && abs((offset - n * offset.dot(n)).length - rim.radius) <= tolerance.distance
        }
        for (faceIndex, faceID) in shell.faceIDs.enumerated() {
            let source = try SourceBRepFacePatchBuilder().build(faceID: faceID, stableID: "source-face:\(faceIndex)", from: model,
                                                                sourceSubshapes: context.subshapes.entries, tolerance: tolerance).patch
            let isCap = rim.capFaceIDs.contains(faceID)
            guard isCap || rim.wallFaceIDs.contains(faceID) else {
                if source.loops.contains(where: { $0.edges.contains { onRim($0.startPoint) || onRim($0.endPoint) } }) {
                    throw refuse("A conical rim's vertices lie only on its cap and its cone.")
                }
                patches.append(source)
                continue
            }
            let loops = try source.loops.map { loop in
                BRepSewingLoop(stableID: loop.stableID, role: loop.role, edges: try loop.edges.map { edge in
                    if isRim(edge) {
                        let middle = try edge.curve.point(at: (edge.startParameter + edge.endParameter) / 2, tolerance: tolerance)
                        let moved = isCap
                            ? try arc(from: try onCap(edge.startPoint), through: try onCap(middle), to: try onCap(edge.endPoint),
                                      on: Circle3D(center: rim.center, normal: n, radius: capRadius), edge.stableID, edge.parentSubshapeIDs)
                            : try arc(from: try onWall(edge.startPoint), through: try onWall(middle), to: try onWall(edge.endPoint),
                                      on: Circle3D(center: rim.center + n * wallDrop, normal: n, radius: wallRadius), edge.stableID,
                                      edge.parentSubshapeIDs)
                        guard case let .circle(circle) = moved.curve else { return edge }
                        let pcurve: SurfaceParameterCurve
                        if isCap {
                            pcurve = try planarCirclePcurve(circle, from: moved.startParameter, to: moved.endParameter, on: source.surface)
                        } else {
                            // The cone's own chart: the old rim's turn at the moved rim's slant.
                            let (a, b) = (try edge.surfaceParameterCurve.parameter(atNormalizedFraction: 0, tolerance: tolerance),
                                          try edge.surfaceParameterCurve.parameter(atNormalizedFraction: 1, tolerance: tolerance))
                            let v = try source.surface.parameterProjection(of: moved.startPoint, tolerance: tolerance).v
                            pcurve = .constantV(v: v, uStart: a.u, uEnd: b.u)
                        }
                        return BRepSewingEdge(stableID: edge.stableID, curve: moved.curve, startParameter: moved.startParameter,
                                              endParameter: moved.endParameter, startPoint: moved.startPoint, endPoint: moved.endPoint,
                                              surfaceParameterCurve: pcurve, parentSubshapeIDs: edge.parentSubshapeIDs,
                                              startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                                              endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs)
                    }
                    let (startOnRim, endOnRim) = (onRim(edge.startPoint), onRim(edge.endPoint))
                    guard startOnRim || endOnRim else { return edge }
                    // A seam from the rim, across the cap or down the cone, now from the contact.
                    guard isLine(edge.curve) else {
                        throw refuse("A conical rim's cap and cone meet it only along straight seams.")
                    }
                    let contact = { (point: Point3D) throws -> Point3D in isCap ? try onCap(point) : try onWall(point) }
                    let (p, q) = (startOnRim ? try contact(edge.startPoint) : edge.startPoint,
                                  endOnRim ? try contact(edge.endPoint) : edge.endPoint)
                    let delta = q - p
                    let span = edge.endPoint - edge.startPoint
                    let moved = startOnRim ? p - edge.startPoint : q - edge.endPoint
                    guard delta.length > tolerance.distance, delta.dot(span) > 0,
                          moved.cross(span).length <= tolerance.distance * span.length else {
                        throw KernelError(phase: .evaluation, code: .topologyFailure, featureID: featureID, tolerance: tolerance,
                                          message: "A conical rim's blend reaches past a seam of its cap or its cone.")
                    }
                    let (oldA, oldB) = (try edge.surfaceParameterCurve.parameter(atNormalizedFraction: 0, tolerance: tolerance),
                                        try edge.surfaceParameterCurve.parameter(atNormalizedFraction: 1, tolerance: tolerance))
                    func carried(_ point: Point3D, _ old: SurfaceParameter) throws -> SurfaceParameter {
                        let projected = try source.surface.parameterProjection(of: point, tolerance: tolerance)
                        // The cone's chart keeps the seam's turn; the cap's plane takes the point as it is.
                        return isCap ? SurfaceParameter(u: projected.u, v: projected.v) : SurfaceParameter(u: old.u, v: projected.v)
                    }
                    let a = startOnRim ? try carried(p, oldA) : oldA
                    let b = endOnRim ? try carried(q, oldB) : oldB
                    return BRepSewingEdge(stableID: edge.stableID,
                                          curve: .line(Line3D(origin: p, direction: try delta.normalized(tolerance: tolerance.distance))),
                                          startParameter: 0, endParameter: delta.length, startPoint: p, endPoint: q,
                                          surfaceParameterCurve: .polyline([a, b]), parentSubshapeIDs: edge.parentSubshapeIDs,
                                          startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                                          endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs)
                })
            }
            patches.append(BRepSewingFacePatch(stableID: source.stableID, surface: source.surface, orientation: source.orientation,
                                               loops: loops, parentSubshapeIDs: source.parentSubshapeIDs))
        }
        return BRepSewingRequest(featureID: featureID, bodyKind: .solid, shells: [BRepSewingShell(stableID: "shell:0", patches: patches)],
                                 bodyParentSubshapeIDs: context.subshapeIDs(for: .body(bodyID)))
    }

    /// The band's outward normal at the middle of its section through `point`: away from the
    /// material the round or chamfer leaves.
    private func outward(at point: Point3D, rim: Rim, section: Section, roundCenter: (radial: Double, normal: Double)?,
                         capContact: Double, wallContact: Double) throws -> Vector3D {
        let n = rim.normal
        let offset = point - rim.center
        let e = try (offset - n * offset.dot(n)).normalized(tolerance: tolerance.distance)
        // The material lies across the cap from its outward normal and across the cone from where
        // the cap lies: the corner's wedge holds it when the cone runs below the cap.
        let cut = rim.wall.normal < 0
        let corner = rim.center + e * rim.radius
        if let roundCenter {
            let center = rim.center + e * (rim.radius + roundCenter.radial) + n * roundCenter.normal
            let towardCorner = try (corner - center).normalized(tolerance: tolerance.distance)
            // A cut leaves the ball's side solid, its corner side empty; a fill the reverse.
            return cut ? towardCorner : towardCorner * -1
        }
        let capPoint = corner + e * (rim.capSide * capContact)
        let wallPoint = corner + e * (rim.wall.radial * wallContact) + n * (rim.wall.normal * wallContact)
        let line = wallPoint - capPoint
        let toCorner = corner - capPoint
        let normal = try (toCorner - line * (toCorner.dot(line) / line.dot(line))).normalized(tolerance: tolerance.distance)
        return cut ? normal : normal * -1
    }

    /// A band patch about the axis from its loop of arcs and sections, each trimming curve an
    /// iso line carried from `reference`'s parameters, the loop counterclockwise about `outward`.
    private func bandPatch(_ stableID: String, edges: [BRepSewingEdge], on surface: Surface3D, reference: Point3D,
                           outward: Vector3D, across: Vector3D, parents: [SubshapeID]) throws -> BRepSewingFacePatch {
        let anchor = try surface.parameterProjection(of: reference, tolerance: tolerance)
        let periodicV: Bool
        if case .analytic(.torus) = surface { periodicV = true } else { periodicV = false }
        func carried(_ point: Point3D) throws -> SurfaceParameter {
            let raw = try surface.parameterProjection(of: point, tolerance: tolerance)
            return SurfaceParameter(u: anchor.u + remainder(raw.u - anchor.u, 2 * Double.pi),
                                    v: periodicV ? anchor.v + remainder(raw.v - anchor.v, 2 * Double.pi) : raw.v)
        }
        let loop = try edges.map { edge -> BRepSewingEdge in
            let middle = try edge.curve.point(at: (edge.startParameter + edge.endParameter) / 2, tolerance: tolerance)
            let (a, m, b) = (try carried(edge.startPoint), try carried(middle), try carried(edge.endPoint))
            let pcurve: SurfaceParameterCurve
            if abs(a.u - m.u) <= tolerance.angle && abs(m.u - b.u) <= tolerance.angle {
                // A section: across the band at one turn, through its middle.
                let vEnd = periodicV ? a.v + remainder(m.v - a.v, 2 * Double.pi) + remainder(b.v - m.v, 2 * Double.pi) : b.v
                pcurve = .constantU(u: a.u, vStart: a.v, vEnd: vEnd)
            } else {
                let du = remainder(m.u - a.u, 2 * Double.pi) + remainder(b.u - m.u, 2 * Double.pi)
                pcurve = .constantV(v: a.v, uStart: a.u, uEnd: a.u + du)
            }
            return BRepSewingEdge(stableID: edge.stableID, curve: edge.curve, startParameter: edge.startParameter,
                                  endParameter: edge.endParameter, startPoint: edge.startPoint, endPoint: edge.endPoint,
                                  surfaceParameterCurve: pcurve, parentSubshapeIDs: edge.parentSubshapeIDs)
        }
        // The loop runs along the cap contact first; the band lies to its left about the outward
        // normal when it reaches across toward the wall contact there.
        let first = loop[0]
        let tangent = try first.curve.point(at: first.startParameter + (first.endParameter - first.startParameter) * 0.51, tolerance: tolerance)
            - (try first.curve.point(at: first.startParameter + (first.endParameter - first.startParameter) * 0.49, tolerance: tolerance))
        let counterclockwise = outward.cross(tangent).dot(across) > 0
        let oriented = counterclockwise ? loop : try loop.reversed().map(reversed)
        let at = try surface.parameterProjection(of: reference, tolerance: tolerance)
        let natural = try surface.normal(u: at.u, v: at.v, tolerance: tolerance)
        return BRepSewingFacePatch(stableID: stableID, surface: surface, orientation: natural.dot(outward) >= 0 ? .forward : .reversed,
                                   loops: [BRepSewingLoop(stableID: "\(stableID):outer", role: .outer, edges: oriented)],
                                   parentSubshapeIDs: parents)
    }

    // MARK: - Finding the rim

    private func rim(of edgeIDs: [EdgeID], model: BRepModel) throws -> Rim? {
        guard let firstID = edgeIDs.first, let first = model.edges[firstID],
              let circle = circleOf(model.geometry.curves[first.curveID]) else { return nil }
        func uses(_ edgeID: EdgeID) -> [FaceID] {
            model.faces.filter { _, face in face.loops.contains { model.loops[$0]?.edges.contains { $0.edgeID == edgeID } ?? false } }
                .map(\.key).sorted()
        }
        guard let shell = model.shells.values.first(where: { shell in uses(firstID).allSatisfy(shell.faceIDs.contains) }) else { return nil }
        // Every edge of the shell on the circle: the rim, a closed chain of arcs.
        let shellEdgeIDs = Set(shell.faceIDs.flatMap { faceID in
            (model.faces[faceID]?.loops ?? []).flatMap { model.loops[$0]?.edges.map(\.edgeID) ?? [] }
        })
        let arcEdgeIDs = shellEdgeIDs.filter { edgeID in
            guard let edge = model.edges[edgeID], let arc = circleOf(model.geometry.curves[edge.curveID]) else { return false }
            return arc.center.isApproximatelyEqual(to: circle.center, tolerance: tolerance.distance)
                && abs(arc.radius - circle.radius) <= tolerance.distance
                && arc.normal.cross(circle.normal).length <= tolerance.angle * max(arc.normal.length * circle.normal.length, 1)
        }.sorted()
        guard Set(edgeIDs).isSubset(of: Set(arcEdgeIDs)) else { return nil }
        var degree: [VertexID: Int] = [:]
        for edgeID in arcEdgeIDs {
            guard let edge = model.edges[edgeID] else { return nil }
            degree[edge.startVertexID, default: 0] += 1
            degree[edge.endVertexID, default: 0] += 1
        }
        guard degree.values.allSatisfy({ $0 == 2 }) else { return nil }
        // Each arc between a planar cap facing one way and one coaxial cone.
        var normal: Vector3D?
        var capFaceIDs: Set<FaceID> = []
        var wallFaceIDs: Set<FaceID> = []
        var cone: (apex: Point3D, axis: Vector3D, halfAngle: Double)?
        for edgeID in arcEdgeIDs {
            let faceIDs = uses(edgeID)
            guard faceIDs.count == 2 else { return nil }
            var capNormal: Vector3D?
            var wallCone: (FaceID, Point3D, Vector3D, Double)?
            for faceID in faceIDs {
                guard let face = model.faces[faceID] else { return nil }
                switch model.geometry.surfaces[face.surfaceID] {
                case let .plane(plane)?:
                    capNormal = try outwardNormal(plane.normal, face: face, faceID: faceID, model: model)
                    capFaceIDs.insert(faceID)
                case let .analytic(.plane(_, planeNormal))?:
                    capNormal = try outwardNormal(planeNormal, face: face, faceID: faceID, model: model)
                    capFaceIDs.insert(faceID)
                case let .analytic(.cone(apex, axis, halfAngle))?:
                    wallCone = (faceID, apex, axis, halfAngle)
                default:
                    return nil
                }
            }
            guard let capNormal, let wallCone, capNormal.cross(circle.normal).length <= tolerance.angle * max(circle.normal.length, 1) else {
                return nil
            }
            if let normal, normal.dot(capNormal) < 1 - tolerance.angle { return nil }
            normal = normal ?? capNormal
            if let cone {
                guard cone.apex.isApproximatelyEqual(to: wallCone.1, tolerance: tolerance.distance),
                      abs(abs(cone.axis.dot(wallCone.2)) - 1) <= tolerance.angle, abs(cone.halfAngle - wallCone.3) <= tolerance.angle else { return nil }
            } else {
                cone = (wallCone.1, wallCone.2, wallCone.3)
            }
            wallFaceIDs.insert(wallCone.0)
        }
        guard let normal, let cone, capFaceIDs.isDisjoint(with: wallFaceIDs) else { return nil }
        // The cone's axis is the rim's: through its centre, along the cap's normal.
        let toCenter = circle.center - cone.apex
        guard cone.axis.cross(normal).length <= tolerance.angle * max(cone.axis.length, 1),
              (toCenter - cone.axis * toCenter.dot(cone.axis)).length <= tolerance.distance else { return nil }
        /// The sign of `measure` over the faces' vertices off the rim, the same for all; 0 when none is.
        func side(of faceIDs: Set<FaceID>, _ measure: (Point3D) -> Double) -> Double? {
            var side = 0.0
            for faceID in faceIDs {
                for loopID in model.faces[faceID]?.loops ?? [] {
                    for use in model.loops[loopID]?.edges ?? [] {
                        guard let edge = model.edges[use.edgeID] else { return nil }
                        for vertexID in [edge.startVertexID, edge.endVertexID] {
                            guard let point = model.vertices[vertexID]?.point else { return nil }
                            let value = measure(point)
                            guard abs(value) > tolerance.distance else { continue }
                            if side != 0, (value > 0) != (side > 0) { return nil }
                            side = value > 0 ? 1 : -1
                        }
                    }
                }
            }
            return side
        }
        // The cone runs from the cap the way its vertices lie; the cap lies outside the circle
        // when its vertices off the rim do, and inside it (a disc) when it has none.
        guard let wallSide = side(of: wallFaceIDs, { ($0 - circle.center).dot(normal) }), wallSide != 0,
              let capSide = side(of: capFaceIDs, { point in
                  let offset = point - circle.center
                  return (offset - normal * offset.dot(normal)).length - circle.radius
              }),
              let vertex = model.vertices[first.startVertexID]?.point else { return nil }
        var generator = try (vertex - cone.apex).normalized(tolerance: tolerance.distance)
        if (generator.dot(normal) > 0) != (wallSide > 0) { generator = generator * -1 }
        let offset = vertex - circle.center
        let e = try (offset - normal * offset.dot(normal)).normalized(tolerance: tolerance.distance)
        return Rim(capFaceIDs: capFaceIDs, center: circle.center, radius: circle.radius, normal: normal,
                   capSide: capSide == 0 ? -1 : capSide, wall: (generator.dot(e), generator.dot(normal)),
                   arcEdgeIDs: arcEdgeIDs, wallFaceIDs: wallFaceIDs)
    }

    /// A planar face's normal facing out of its shell.
    private func outwardNormal(_ normal: Vector3D, face: Face, faceID: FaceID, model: BRepModel) throws -> Vector3D {
        let shellReversed = model.shells.values.first { $0.faceIDs.contains(faceID) }?.orientation == .reversed
        let flip = (face.orientation == .reversed) != shellReversed
        return try (flip ? normal * -1 : normal).normalized(tolerance: tolerance.distance)
    }

    /// Refuses a cap whose edges away from the rim the moved rim would reach: an outline's holes
    /// inside the cap contact, or a hole's outline outside it. Seams reaching the rim are
    /// shortened with it and checked there.
    private func checkCapClear(_ rim: Rim, capRadius: Double, model: BRepModel, refuse: (String) -> KernelError) throws {
        func radial(_ point: Point3D) -> Double {
            let offset = point - rim.center
            return (offset - rim.normal * offset.dot(rim.normal)).length
        }
        func onRim(_ point: Point3D) -> Bool {
            abs((point - rim.center).dot(rim.normal)) <= tolerance.distance && abs(radial(point) - rim.radius) <= tolerance.distance
        }
        for faceID in rim.capFaceIDs {
            for loopID in model.faces[faceID]?.loops ?? [] {
                for use in model.loops[loopID]?.edges ?? [] where rim.arcEdgeIDs.contains(use.edgeID) == false {
                    guard let edge = model.edges[use.edgeID], let start = model.vertices[edge.startVertexID]?.point,
                          let end = model.vertices[edge.endVertexID]?.point else {
                        throw TopologyError.missingReference("Missing cap edge.")
                    }
                    guard onRim(start) == false, onRim(end) == false else { continue }
                    let reach: [Double]
                    if let circle = circleOf(model.geometry.curves[edge.curveID]) {
                        let offset = (circle.center - rim.center).length
                        reach = [offset + circle.radius, abs(offset - circle.radius)]
                    } else {
                        reach = [radial(start), radial(end)]
                    }
                    let clear = rim.capSide < 0
                        ? reach.allSatisfy { $0 < capRadius - tolerance.distance }
                        : reach.allSatisfy { $0 > capRadius + tolerance.distance }
                    guard clear else { throw refuse("A conical rim's blend reaches another edge of its cap.") }
                }
            }
        }
    }

    /// A circle however the curve spells it.
    private func circleOf(_ curve: Curve3D?) -> Circle3D? {
        switch curve {
        case let .circle(circle)?: circle
        case let .analytic(.circle(center, normal, radius))?: Circle3D(center: center, normal: normal, radius: radius)
        case let .analytic(.arc(center, normal, radius, _, _))?: Circle3D(center: center, normal: normal, radius: radius)
        default: nil
        }
    }

    private func isLine(_ curve: Curve3D) -> Bool {
        switch curve {
        case .line, .analytic(.line): true
        default: false
        }
    }

    /// A rim arc's start, middle and end as its edge runs: the middle of its trimmed interval, or
    /// of the shorter way round between its ends.
    private func arcPoints(_ edgeID: EdgeID, model: BRepModel) throws -> (Point3D, Point3D, Point3D) {
        guard let edge = model.edges[edgeID], let curve = model.geometry.curves[edge.curveID], let circle = circleOf(curve),
              let start = model.vertices[edge.startVertexID]?.point, let end = model.vertices[edge.endVertexID]?.point else {
            throw TopologyError.missingReference("Missing rim arc.")
        }
        if let trim = edge.trim {
            return (start, try curve.point(at: (trim.startParameter + trim.endParameter) / 2, tolerance: tolerance), end)
        }
        let plain = Curve3D.circle(circle)
        let t0 = try plain.parameterProjection(of: start, tolerance: tolerance).parameter
        let t1 = try plain.parameterProjection(of: end, tolerance: tolerance).parameter
        return (start, try plain.point(at: t0 + remainder(t1 - t0, 2 * Double.pi) / 2, tolerance: tolerance), end)
    }

    /// The arc of `circle` from `start` through `middle` to `end`.
    private func arc(from start: Point3D, through middle: Point3D, to end: Point3D, on circle: Circle3D, _ stableID: String,
                     _ parents: [SubshapeID]) throws -> BRepSewingEdge {
        let curve = Curve3D.circle(circle)
        let t0 = try curve.parameterProjection(of: start, tolerance: tolerance).parameter
        let tm = try curve.parameterProjection(of: middle, tolerance: tolerance).parameter
        let t1 = try curve.parameterProjection(of: end, tolerance: tolerance).parameter
        let halfway = t0 + remainder(tm - t0, 2 * Double.pi)
        return BRepSewingEdge(stableID: stableID, curve: curve, startParameter: t0, endParameter: halfway + remainder(t1 - halfway, 2 * Double.pi),
                              startPoint: start, endPoint: end, surfaceParameterCurve: .polyline([]), parentSubshapeIDs: parents)
    }

    private func planarCirclePcurve(_ circle: Circle3D, from t0: Double, to t1: Double, on surface: Surface3D) throws -> SurfaceParameterCurve {
        let curve = Curve3D.circle(circle)
        let center = try surface.parameterProjection(of: circle.center, tolerance: tolerance)
        let cosine = try surface.parameterProjection(of: curve.point(at: 0, tolerance: tolerance), tolerance: tolerance)
        let sine = try surface.parameterProjection(of: curve.point(at: Double.pi / 2, tolerance: tolerance), tolerance: tolerance)
        return .harmonic(center: Point2D(x: center.u, y: center.v), cosine: Point2D(x: cosine.u - center.u, y: cosine.v - center.v),
                         sine: Point2D(x: sine.u - center.u, y: sine.v - center.v), startParameter: t0, endParameter: t1)
    }

    private func reversed(_ edge: BRepSewingEdge) throws -> BRepSewingEdge {
        BRepSewingEdge(stableID: edge.stableID, curve: edge.curve, startParameter: edge.endParameter, endParameter: edge.startParameter,
                       startPoint: edge.endPoint, endPoint: edge.startPoint,
                       surfaceParameterCurve: try edge.surfaceParameterCurve.reversed(tolerance: tolerance),
                       parentSubshapeIDs: edge.parentSubshapeIDs,
                       startVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs,
                       endVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs)
    }
}
