import Foundation
import CADCore
import CADGeometry
import CADTopology

/// Fillet Shell's Full round across an annular planar cap — a tube's end — between its outer and
/// inner rims: each rim a closed loop of arcs of one circle, the circles coaxial, each rim's wall the
/// coaxial cylinder running down from the cap. The round is the half torus about the axis, its tube
/// half the cap's width wide, its centre circle midway between the rims a tube radius below the cap,
/// so it touches both walls and the cap's plane. The cap goes; each wall's rim moves down the tube
/// radius. The torus is one patch per stretch between the rims' joints (the rims split at the same
/// angles), meeting the next on a half circle across the tube.
package struct FullRimRoundBuilder {
    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// An annular cap's rims about their axis.
    private struct Rims {
        let capFaceID: FaceID
        let center: Point3D
        let normal: Vector3D
        let outer: (radius: Double, loopID: LoopID)
        let inner: (radius: Double, loopID: LoopID)
    }

    /// Whether the two edges are arcs on the two rims of an annular planar cap.
    package func admits(_ first: EdgeID, _ second: EdgeID, model: BRepModel) throws -> Bool {
        try rims(first, second, model: model) != nil
    }

    /// The round's tube radius: half the cap's width.
    package func radius(_ first: EdgeID, _ second: EdgeID, model: BRepModel) throws -> Double? {
        try rims(first, second, model: model).map { ($0.outer.radius - $0.inner.radius) / 2 }
    }

    package func request(featureID: FeatureID, bodyID: BodyID, edges: (EdgeID, EdgeID), parents selected: [SubshapeID],
                         context: EvaluationContext) throws -> BRepSewingRequest {
        let model = context.brep
        func refuse(_ message: String) -> KernelError {
            KernelError(phase: .evaluation, code: .unsupportedCapability, featureID: featureID, tolerance: tolerance, message: message)
        }
        guard let rims = try rims(edges.0, edges.1, model: model) else {
            throw refuse("A full round across a tube's end takes an arc of each of its rims.")
        }
        guard let body = model.bodies[bodyID], body.kind == .solid, body.shellIDs.count == 1,
              let shell = model.shells[body.shellIDs[0]], shell.faceIDs.contains(rims.capFaceID) else {
            throw refuse("A full round across a tube's end rounds one single-shell solid.")
        }
        let rho = (rims.outer.radius - rims.inner.radius) / 2
        let middle = (rims.outer.radius + rims.inner.radius) / 2
        let n = rims.normal
        let down = n * -rho
        // The rims' joints, as angles about the axis, the same on both rims.
        let basis = try planeBasis(n)
        func angle(_ point: Point3D) -> Double {
            let offset = point - rims.center
            var value = atan2(offset.dot(basis.1), offset.dot(basis.0))
            if value < 0 { value += 2 * Double.pi }
            return value
        }
        let outerJoints = try joints(rims.outer.loopID, model: model).map(angle).sorted()
        let innerJoints = try joints(rims.inner.loopID, model: model).map(angle).sorted()
        guard outerJoints.count == innerJoints.count, outerJoints.count >= 2,
              zip(outerJoints, innerJoints).allSatisfy({ abs($0 - $1) <= tolerance.angle }) else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): rims split at different angles need their walls'
            // rims split to match the torus's patches, which is not built, so they are refused.
            // Production path: FullRimRoundBuilder for Full fillets across a tube's end. Complete
            // only when such rims round, verified by a tube whose rims are split differently.
            throw refuse("A full round across a tube's end takes rims split at the same angles.")
        }
        let torus = Surface3D.analytic(.torus(center: rims.center + down, axis: n, majorRadius: middle, minorRadius: rho))
        func onCircle(_ radius: Double, _ theta: Double, lift: Double = 0) -> Point3D {
            rims.center + down + (basis.0 * cos(theta) + basis.1 * sin(theta)) * radius + n * lift
        }
        func arc(_ radius: Double, from a: Double, to b: Double, _ stableID: String) throws -> BRepSewingEdge {
            let circle = Circle3D(center: rims.center + down, normal: n, radius: radius)
            let curve = Curve3D.circle(circle)
            let (p, q) = (onCircle(radius, a), onCircle(radius, b))
            let t0 = try curve.parameterProjection(of: p, tolerance: tolerance).parameter
            var span = try curve.parameterProjection(of: q, tolerance: tolerance).parameter - t0
            // Turning as the angles do, by their difference.
            let turn = b - a
            span = turn + 2 * Double.pi * ((span - turn) / (2 * Double.pi)).rounded()
            return BRepSewingEdge(stableID: stableID, curve: curve, startParameter: t0, endParameter: t0 + span, startPoint: p, endPoint: q,
                                  surfaceParameterCurve: .polyline([]), parentSubshapeIDs: selected)
        }
        /// The half circle across the tube at `theta`, from the outer contact over the top to the
        /// inner one, or back.
        func section(_ theta: Double, outward: Bool, _ stableID: String) throws -> BRepSewingEdge {
            let radial = basis.0 * cos(theta) + basis.1 * sin(theta)
            let circle = Circle3D(center: rims.center + down + radial * middle, normal: n.cross(radial), radius: rho)
            let curve = Curve3D.circle(circle)
            let (outerPoint, innerPoint, top) = (onCircle(rims.outer.radius, theta), onCircle(rims.inner.radius, theta),
                                                 onCircle(middle, theta, lift: rho))
            let (p, q) = outward ? (innerPoint, outerPoint) : (outerPoint, innerPoint)
            let t0 = try curve.parameterProjection(of: p, tolerance: tolerance).parameter
            let tm = try curve.parameterProjection(of: top, tolerance: tolerance).parameter
            let tq = try curve.parameterProjection(of: q, tolerance: tolerance).parameter
            func near(_ from: Double, _ to: Double) -> Double { from + remainder(to - from, 2 * Double.pi) }
            let viaTop = near(t0, tm)
            return BRepSewingEdge(stableID: stableID, curve: curve, startParameter: t0, endParameter: near(viaTop, tq),
                                  startPoint: p, endPoint: q, surfaceParameterCurve: .polyline([]), parentSubshapeIDs: selected)
        }
        // The torus's patches, each from one joint to the next.
        let faceParents = context.subshapeIDs(for: .face(rims.capFaceID))
        var patches: [BRepSewingFacePatch] = []
        let thetas = outerJoints + [outerJoints[0] + 2 * Double.pi]
        for k in 0..<outerJoints.count {
            let (a, b) = (thetas[k], thetas[k + 1])
            let edges = [
                try arc(rims.outer.radius, from: a, to: b, "rim-round:\(k):outer-rim"),
                try section(b, outward: false, "rim-round:\(k):end"),
                try arc(rims.inner.radius, from: b, to: a, "rim-round:\(k):inner-rim"),
                try section(a, outward: true, "rim-round:\(k):start"),
            ]
            patches.append(try torusPatch("rim-round:\(k)", edges: edges, on: torus, reference: onCircle(middle, a, lift: rho),
                                          parents: faceParents))
        }
        // The walls' rims moved down the tube radius; the cap gone; every other face as it was.
        for (faceIndex, faceID) in shell.faceIDs.enumerated() where faceID != rims.capFaceID {
            let source = try SourceBRepFacePatchBuilder().build(faceID: faceID, stableID: "source-face:\(faceIndex)", from: model,
                                                                sourceSubshapes: context.subshapes.entries, tolerance: tolerance).patch
            func onCap(_ point: Point3D) -> Bool { abs((point - rims.center).dot(n)) <= tolerance.distance }
            guard source.loops.contains(where: { $0.edges.contains { onCap($0.startPoint) || onCap($0.endPoint) } }) else {
                patches.append(source)
                continue
            }
            let loops = try source.loops.map { loop in
                BRepSewingLoop(stableID: loop.stableID, role: loop.role, edges: try loop.edges.map { edge in
                    switch (onCap(edge.startPoint), onCap(edge.endPoint)) {
                    case (false, false):
                        return edge
                    case (true, true):
                        // A rim arc, one circle lower.
                        guard case let .circle(circle) = edge.curve else { throw refuse("A tube's rims are arcs.") }
                        let lowered = Circle3D(center: circle.center + down, normal: circle.normal, radius: circle.radius)
                        let (p, q) = (edge.startPoint + down, edge.endPoint + down)
                        // The wall's own chart: its old trimming curve's turn, at the lowered height.
                        let (a, b) = (try edge.surfaceParameterCurve.parameter(atNormalizedFraction: 0, tolerance: tolerance),
                                      try edge.surfaceParameterCurve.parameter(atNormalizedFraction: 1, tolerance: tolerance))
                        let v = try source.surface.parameterProjection(of: p, tolerance: tolerance).v
                        return BRepSewingEdge(stableID: edge.stableID, curve: .circle(lowered), startParameter: edge.startParameter,
                                              endParameter: edge.endParameter, startPoint: p, endPoint: q,
                                              surfaceParameterCurve: .constantV(v: v, uStart: a.u, uEnd: b.u),
                                              parentSubshapeIDs: edge.parentSubshapeIDs,
                                              startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                                              endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs)
                    default:
                        // A seam down the wall from the rim, shortened by the tube radius.
                        guard case .line = edge.curve else { throw refuse("A tube's walls are joined along straight seams.") }
                        let (p, q) = (onCap(edge.startPoint) ? edge.startPoint + down : edge.startPoint,
                                      onCap(edge.endPoint) ? edge.endPoint + down : edge.endPoint)
                        let delta = q - p
                        guard delta.dot(edge.endPoint - edge.startPoint) > tolerance.distance * delta.length else {
                            throw KernelError(phase: .evaluation, code: .topologyFailure, featureID: featureID, tolerance: tolerance,
                                              message: "A tube's full round reaches past the bottom of its walls.")
                        }
                        // The wall's own chart: the old trimming curve's ends, the moved one at its new height.
                        let (oldA, oldB) = (try edge.surfaceParameterCurve.parameter(atNormalizedFraction: 0, tolerance: tolerance),
                                            try edge.surfaceParameterCurve.parameter(atNormalizedFraction: 1, tolerance: tolerance))
                        let a = SurfaceParameter(u: oldA.u, v: try source.surface.parameterProjection(of: p, tolerance: tolerance).v)
                        let b = SurfaceParameter(u: oldB.u, v: try source.surface.parameterProjection(of: q, tolerance: tolerance).v)
                        return BRepSewingEdge(stableID: edge.stableID,
                                              curve: .line(Line3D(origin: p, direction: try delta.normalized(tolerance: tolerance.distance))),
                                              startParameter: 0, endParameter: delta.length, startPoint: p, endPoint: q,
                                              surfaceParameterCurve: .polyline([SurfaceParameter(u: a.u, v: a.v), SurfaceParameter(u: b.u, v: b.v)]),
                                              parentSubshapeIDs: edge.parentSubshapeIDs,
                                              startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                                              endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs)
                    }
                })
            }
            patches.append(BRepSewingFacePatch(stableID: source.stableID, surface: source.surface, orientation: source.orientation,
                                               loops: loops, parentSubshapeIDs: source.parentSubshapeIDs))
        }
        return BRepSewingRequest(featureID: featureID, bodyKind: .solid, shells: [BRepSewingShell(stableID: "shell:0", patches: patches)],
                                 bodyParentSubshapeIDs: context.subshapeIDs(for: .body(bodyID)))
    }

    /// A torus patch from its loop of circles: each edge's trimming curve an iso line of the torus,
    /// carried on from `reference`'s parameters so the loop closes, facing up out of the tube.
    private func torusPatch(_ stableID: String, edges: [BRepSewingEdge], on torus: Surface3D, reference: Point3D,
                            parents: [SubshapeID]) throws -> BRepSewingFacePatch {
        let anchor = try torus.parameterProjection(of: reference, tolerance: tolerance)
        func carried(_ point: Point3D) throws -> SurfaceParameter {
            let raw = try torus.parameterProjection(of: point, tolerance: tolerance)
            return SurfaceParameter(u: anchor.u + remainder(raw.u - anchor.u, 2 * Double.pi),
                                    v: anchor.v + remainder(raw.v - anchor.v, 2 * Double.pi))
        }
        let loop = try edges.map { edge -> BRepSewingEdge in
            let middle = try edge.curve.point(at: (edge.startParameter + edge.endParameter) / 2, tolerance: tolerance)
            let (a, m, b) = (try carried(edge.startPoint), try carried(middle), try carried(edge.endPoint))
            let pcurve: SurfaceParameterCurve
            if abs(a.u - m.u) <= tolerance.angle && abs(m.u - b.u) <= tolerance.angle {
                pcurve = .constantU(u: a.u, vStart: a.v, vEnd: b.v)
            } else {
                // Along a rim: the turn from the start through the middle to the end.
                let du = remainder(m.u - a.u, 2 * Double.pi) + remainder(b.u - m.u, 2 * Double.pi)
                pcurve = .constantV(v: a.v, uStart: a.u, uEnd: a.u + du)
            }
            return BRepSewingEdge(stableID: edge.stableID, curve: edge.curve, startParameter: edge.startParameter,
                                  endParameter: edge.endParameter, startPoint: edge.startPoint, endPoint: edge.endPoint,
                                  surfaceParameterCurve: pcurve, parentSubshapeIDs: edge.parentSubshapeIDs)
        }
        // Facing away from the material, up out of the tube at the top of its section: the loop as
        // built runs counterclockwise in the torus's parameters; facing against the torus's own
        // normal, the face is the torus reversed and the loop runs back.
        let top = try torus.parameterProjection(of: reference, tolerance: tolerance)
        let normal = try torus.normal(u: top.u, v: top.v, tolerance: tolerance)
        guard case let .analytic(.torus(_, axis, _, _)) = torus else { throw TopologyError.missingReference("A rim round's torus is missing.") }
        let forward = normal.dot(axis) >= 0
        let edges = forward ? loop : try loop.reversed().map { edge in
            BRepSewingEdge(stableID: edge.stableID, curve: edge.curve, startParameter: edge.endParameter, endParameter: edge.startParameter,
                           startPoint: edge.endPoint, endPoint: edge.startPoint,
                           surfaceParameterCurve: try edge.surfaceParameterCurve.reversed(tolerance: tolerance),
                           parentSubshapeIDs: edge.parentSubshapeIDs)
        }
        return BRepSewingFacePatch(stableID: stableID, surface: torus, orientation: forward ? .forward : .reversed,
                                   loops: [BRepSewingLoop(stableID: "\(stableID):outer", role: .outer, edges: edges)],
                                   parentSubshapeIDs: parents)
    }

    // MARK: - Finding the rims

    private func rims(_ first: EdgeID, _ second: EdgeID, model: BRepModel) throws -> Rims? {
        for (faceID, face) in model.faces.sorted(by: { $0.key < $1.key }) {
            guard case let .plane(plane)? = model.geometry.surfaces[face.surfaceID], face.loops.count == 2,
                  let loopA = model.loops[face.loops[0]], let loopB = model.loops[face.loops[1]] else { continue }
            let holds = { (loop: Loop, edge: EdgeID) in loop.edges.contains { $0.edgeID == edge } }
            guard (holds(loopA, first) && holds(loopB, second)) || (holds(loopA, second) && holds(loopB, first)) else { continue }
            let normal = try (face.orientation == .forward ? plane.normal : plane.normal * -1).normalized(tolerance: tolerance.distance)
            // Each loop: arcs of one circle about a common centre on the axis.
            func circle(of loop: Loop) -> Circle3D? {
                let circles = loop.edges.compactMap { use -> Circle3D? in
                    guard let edge = model.edges[use.edgeID], case let .circle(circle)? = model.geometry.curves[edge.curveID] else { return nil }
                    return circle
                }
                guard circles.count == loop.edges.count, let first = circles.first,
                      circles.allSatisfy({ $0.center.isApproximatelyEqual(to: first.center, tolerance: tolerance.distance)
                          && abs($0.radius - first.radius) <= tolerance.distance
                          && $0.normal.cross(normal).length <= tolerance.angle * max($0.normal.length, 1) }) else { return nil }
                return first
            }
            guard let a = circle(of: loopA), let b = circle(of: loopB),
                  a.center.isApproximatelyEqual(to: b.center, tolerance: tolerance.distance),
                  abs(a.radius - b.radius) > tolerance.distance else { return nil }
            let (outer, inner) = a.radius > b.radius ? ((a.radius, loopA.id), (b.radius, loopB.id)) : ((b.radius, loopB.id), (a.radius, loopA.id))
            // Each rim's wall: the coaxial cylinder of its radius running down from the cap.
            for (radius, loopID) in [outer, inner] {
                guard let loop = model.loops[loopID] else { return nil }
                for use in loop.edges {
                    let walls = model.faces.filter { otherID, other in
                        otherID != faceID && other.loops.contains { model.loops[$0]?.edges.contains { $0.edgeID == use.edgeID } ?? false }
                    }
                    guard walls.count == 1, let wall = walls.first?.value else { return nil }
                    let axisOK: Bool
                    switch model.geometry.surfaces[wall.surfaceID] {
                    case let .cylinder(cylinder)?:
                        let offset = a.center - cylinder.origin
                        axisOK = cylinder.axis.cross(normal).length <= tolerance.angle * max(cylinder.axis.length, 1)
                            && abs(cylinder.radius - radius) <= tolerance.distance
                            && (offset - cylinder.axis * (offset.dot(cylinder.axis) / cylinder.axis.dot(cylinder.axis))).length <= tolerance.distance
                    case let .analytic(.cylinder(origin, axis, cylinderRadius))?:
                        let offset = a.center - origin
                        axisOK = axis.cross(normal).length <= tolerance.angle * max(axis.length, 1)
                            && abs(cylinderRadius - radius) <= tolerance.distance
                            && (offset - axis * (offset.dot(axis) / axis.dot(axis))).length <= tolerance.distance
                    default:
                        axisOK = false
                    }
                    guard axisOK, try runsDown(wall, from: a.center, normal: normal, model: model) else { return nil }
                }
            }
            return Rims(capFaceID: faceID, center: a.center, normal: normal, outer: outer, inner: inner)
        }
        return nil
    }

    /// Whether every vertex of `face` lies on or below the cap's plane, some strictly.
    private func runsDown(_ face: Face, from point: Point3D, normal: Vector3D, model: BRepModel) throws -> Bool {
        var below = false
        for loopID in face.loops {
            for use in model.loops[loopID]?.edges ?? [] {
                guard let edge = model.edges[use.edgeID] else { throw TopologyError.missingReference("Missing wall edge.") }
                for vertexID in [edge.startVertexID, edge.endVertexID] {
                    guard let p = model.vertices[vertexID]?.point else { throw TopologyError.missingReference("Missing wall vertex.") }
                    let height = (p - point).dot(normal)
                    if height > tolerance.distance { return false }
                    if height < -tolerance.distance { below = true }
                }
            }
        }
        return below
    }

    /// A loop's vertex points.
    private func joints(_ loopID: LoopID, model: BRepModel) throws -> [Point3D] {
        guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("Missing rim loop.") }
        return try loop.edges.map { use in
            guard let edge = model.edges[use.edgeID], let point = model.vertices[edge.startVertexID]?.point else {
                throw TopologyError.missingReference("Missing rim vertex.")
            }
            return point
        }
    }

    private func planeBasis(_ normal: Vector3D) throws -> (Vector3D, Vector3D) {
        let seed = abs(normal.x) < 0.9 ? Vector3D(x: 1, y: 0, z: 0) : Vector3D(x: 0, y: 1, z: 0)
        let u = try (seed - normal * seed.dot(normal)).normalized(tolerance: tolerance.distance)
        return (u, normal.cross(u))
    }
}
