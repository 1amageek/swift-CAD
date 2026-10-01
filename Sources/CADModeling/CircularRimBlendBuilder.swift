import Foundation
import CADCore
import CADGeometry
import CADTopology

/// A round or chamfer across whole circular rims: each rim a circle of edges between a planar cap
/// square to it and the coaxial cylinder running from it — down from it at a convex rim (a solid
/// cylinder's, the cap inside the circle, or a hole's, the cap outside it), up from it at a concave
/// one (a boss on its base, or a blind hole's floor). A round is a band of the torus whose tube
/// of the radius touches the cap and the cylinder, one quarter of the tube turned toward the edge;
/// a chamfer is a band of the 45° cone through both contact circles. The cap shrinks (or its hole
/// grows) by the distance and the cylinder stops the distance short of the cap; a concave rim's band
/// fills the corner instead. A selected edge of
/// a rim takes its whole circle, as a tangent chain does.
package struct CircularRimBlendBuilder {
    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// The band's cross-section: a round's quarter circle (a torus band) or a chamfer's line (a
    /// cone band), each `distance` along the cap and down the wall.
    package enum Section: Sendable {
        case round(Double)
        case chamfer(Double)

        var distance: Double {
            switch self {
            case let .round(distance), let .chamfer(distance): distance
            }
        }
    }

    /// One rim: its circle, the cap's outward normal, which side of the circle the cap lies on,
    /// and its arcs with the cylinder face each bounds.
    private struct Rim {
        let center: Point3D
        /// The cap's outward normal, away from the material.
        let normal: Vector3D
        /// The rim circle's own normal, which the moved circles keep so they run as its arcs do.
        let circleNormal: Vector3D
        let radius: Double
        /// +1 when the cap lies inside the circle (a cylinder's rim), −1 outside (a hole's).
        let side: Double
        /// −1 when the wall runs down from the cap (a convex rim, the band cutting the corner
        /// away), +1 when it rises from it (a concave rim, the band filling the corner).
        let rise: Double
        let capFaceID: FaceID
        let arcs: [(edgeID: EdgeID, cylinderFaceID: FaceID)]
    }

    /// Whether every edge of `edgeIDs` is a circular arc between a plane and a cylinder.
    package static func admits(_ edgeIDs: [EdgeID], model: BRepModel) -> Bool {
        edgeIDs.allSatisfy { edgeID in
            guard let edge = model.edges[edgeID], case .circle = model.geometry.curves[edge.curveID] else { return false }
            return true
        }
    }

    package func request(featureID: FeatureID, bodyID: BodyID, selected: [(edgeID: EdgeID, subshapeID: SubshapeID)],
                         section shape: Section, context: EvaluationContext) throws -> BRepSewingRequest {
        let r = shape.distance
        let model = context.brep
        func refuse(_ message: String) -> KernelError {
            KernelError(phase: .evaluation, code: .unsupportedCapability, featureID: featureID, tolerance: tolerance, message: message)
        }
        guard let body = model.bodies[bodyID], body.kind == .solid, body.shellIDs.count == 1,
              let shell = model.shells[body.shellIDs[0]] else {
            throw refuse("A rim is rounded on one single-shell solid.")
        }
        func faces(of edgeID: EdgeID) throws -> [FaceID] {
            try shell.faceIDs.filter { faceID in
                guard let face = model.faces[faceID] else { throw TopologyError.missingReference("Missing face.") }
                return try face.loops.contains { loopID in
                    guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("Missing loop.") }
                    return loop.edges.contains { $0.edgeID == edgeID }
                }
            }
        }
        func circleOf(_ edgeID: EdgeID) -> Circle3D? {
            guard let edge = model.edges[edgeID], case let .circle(circle) = model.geometry.curves[edge.curveID] else { return nil }
            return circle
        }
        func cylinder(_ faceID: FaceID) -> (origin: Point3D, axis: Vector3D, radius: Double)? {
            guard let face = model.faces[faceID] else { return nil }
            switch model.geometry.surfaces[face.surfaceID] {
            case let .cylinder(cylinder)?: return (cylinder.origin, cylinder.axis, cylinder.radius)
            case let .analytic(.cylinder(origin, axis, radius))?: return (origin, axis, radius)
            default: return nil
            }
        }
        func outward(_ faceID: FaceID, at point: Point3D) throws -> Vector3D {
            guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference("Missing face geometry.")
            }
            let uv = try surface.parameterProjection(of: point, tolerance: tolerance)
            let normal = try surface.normal(u: uv.u, v: uv.v, tolerance: tolerance)
            return face.orientation == .forward ? normal : normal * -1
        }
        // Every rim the selection touches, each with all the arcs of its circle.
        var rims: [Rim] = []
        for selection in selected {
            guard let circle = circleOf(selection.edgeID) else { throw refuse("A rounded rim is circular.") }
            if rims.contains(where: { $0.arcs.contains { $0.edgeID == selection.edgeID } }) { continue }
            let normal = try circle.normal.normalized(tolerance: tolerance.distance)
            let arcs = Set(shell.faceIDs.flatMap { faceID -> [EdgeID] in
                guard let face = model.faces[faceID] else { return [] }
                return face.loops.compactMap { model.loops[$0] }.flatMap { $0.edges.map(\.edgeID) }
            }).filter { edgeID in
                guard let other = circleOf(edgeID) else { return false }
                return other.center.isApproximatelyEqual(to: circle.center, tolerance: tolerance.distance)
                    && abs(other.radius - circle.radius) <= tolerance.distance
                    && other.normal.cross(normal).length <= tolerance.angle
            }.sorted()
            var capFaceID: FaceID?
            var capNormal = normal
            var side = 0.0
            var rise = 0.0
            var bounded: [(EdgeID, FaceID)] = []
            var span = 0.0
            for edgeID in arcs {
                let incident = try faces(of: edgeID)
                guard incident.count == 2, let edge = model.edges[edgeID],
                      let start = model.vertices[edge.startVertexID]?.point, let end = model.vertices[edge.endVertexID]?.point else {
                    throw refuse("A rim's arcs each bound two faces.")
                }
                guard let cap = incident.first(where: { cylinder($0) == nil }), let wall = incident.first(where: { cylinder($0) != nil }),
                      let wallGeometry = cylinder(wall), let capFace = model.faces[cap],
                      case let .plane(plane)? = model.geometry.surfaces[capFace.surfaceID] else {
                    throw refuse("A rim runs between a planar cap and a cylinder.")
                }
                guard capFaceID == nil || capFaceID == cap else { throw refuse("A rim bounds one cap.") }
                capFaceID = cap
                let capOutward = try (capFace.orientation == .forward ? plane.normal : plane.normal * -1).normalized(tolerance: tolerance.distance)
                capNormal = capOutward
                let offset = circle.center - wallGeometry.origin
                guard capOutward.cross(normal).length <= tolerance.angle,
                      wallGeometry.axis.cross(normal).length <= tolerance.angle,
                      abs(wallGeometry.radius - circle.radius) <= tolerance.distance,
                      (offset - wallGeometry.axis * offset.dot(wallGeometry.axis)).length <= tolerance.distance else {
                    throw refuse("A rim's cap is square to its coaxial cylinder.")
                }
                // The cap inside the circle (its outer loop) or outside it (a hole's loop).
                let capLoops = capFace.loops.compactMap { model.loops[$0] }
                let role = capLoops.first(where: { loop in loop.edges.contains(where: { use in use.edgeID == edgeID }) })?.role
                let rimSide: Double = role == .outer ? 1 : -1
                guard side == 0 || side == rimSide else { throw refuse("A rim bounds its cap from one side.") }
                side = rimSide
                // Convex, the wall running down from the cap and facing away from the cap's side of
                // the circle; or concave, rising from it and facing toward that side.
                let middle = try Curve3D.circle(circle).point(at: midParameter(circle, start, end), tolerance: tolerance)
                let radial = try (middle - circle.center).normalized(tolerance: tolerance.distance)
                let wallRise = try wallSide(wall, cap: capOutward, at: circle.center, model: model)
                guard wallRise != 0, rise == 0 || rise == wallRise,
                      abs(try outward(wall, at: middle).dot(radial) * rimSide + wallRise) <= tolerance.angle else {
                    throw refuse("A rim's wall runs straight down or up from its cap, facing across its edge.")
                }
                rise = wallRise
                guard start.isApproximatelyEqual(to: end, tolerance: tolerance.distance) == false else {
                    // FIXME(INCOMPLETE_IMPLEMENTATION): a rim of one closed edge needs its band
                    // split along a seam, which is not built, so it is refused. Production path:
                    // CircularRimBlendBuilder. Complete only when closed rims are rounded,
                    // verified by a revolved disc's rim.
                    throw refuse("A rounded rim is made of arcs.")
                }
                span += abs(try arcSpan(circle, start, end))
                bounded.append((edgeID, wall))
            }
            guard let capFaceID, abs(span - 2 * Double.pi) <= 1e-6 else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): part of a circle's rim would need the round to
                // run out along the rim, which is not built, so only whole rims are rounded.
                // Production path: CircularRimBlendBuilder. Complete only when a rim's arc is
                // rounded alone, verified by a quarter of a cylinder's rim rounded.
                throw refuse("A rounded rim runs all the way around its circle.")
            }
            guard side > 0 ? circle.radius > 2 * r + tolerance.distance : true else {
                throw refuse("A rim's band must fit inside its circle.")
            }
            rims.append(Rim(center: circle.center, normal: capNormal, circleNormal: normal, radius: circle.radius, side: side, rise: rise, capFaceID: capFaceID,
                            arcs: bounded.map { (edgeID: $0.0, cylinderFaceID: $0.1) }))
        }
        let selectedParent: [EdgeID: SubshapeID] = Dictionary(selected.map { ($0.edgeID, $0.subshapeID) }, uniquingKeysWith: { first, _ in first })
        var patches: [BRepSewingFacePatch] = []
        // Where each rim vertex lands on its cap and on its walls.
        var capMoves: [FaceID: [(from: Point3D, to: Point3D)]] = [:]
        var wallMoves: [FaceID: [(from: Point3D, to: Point3D)]] = [:]
        // Each face's rim circles and the circles its rim arcs move to.
        var arcMoves: [FaceID: [(from: Circle3D, to: Circle3D)]] = [:]
        for (rimIndex, rim) in rims.enumerated() {
            let n = rim.normal
            let wallCenter = rim.center + n * (rim.rise * r)
            let capCircle = Circle3D(center: rim.center, normal: rim.circleNormal, radius: rim.radius - rim.side * r)
            let wallCircle = Circle3D(center: wallCenter, normal: rim.circleNormal, radius: rim.radius)
            // The band's surface and the parameters v of its contacts with the cap and the wall: the
            // tube's quarter between the cap (v = π/2) and the wall (v = 0 outside, π inside), or the
            // cone through both contact circles, measured along it from its apex.
            let band: Surface3D
            let (capV, wallV): (Double, Double)
            switch shape {
            case .round:
                // The cap's contact lies straight across the tube from its centre toward the cap,
                // the wall's straight across toward the wall; the band is the quarter between.
                band = .analytic(.torus(center: wallCenter, axis: n, majorRadius: rim.radius - rim.side * r, minorRadius: r))
                let wall = rim.side > 0 ? 0.0 : Double.pi
                (capV, wallV) = (nearestTurn(from: wall, to: -rim.rise * Double.pi / 2), wall)
            case .chamfer:
                // The 45° line from the cap's contact to the wall's meets the axis at the apex.
                let inset = rim.radius - rim.side * r
                band = .analytic(.cone(apex: rim.center + n * (-rim.rise * rim.side * inset), axis: n * (rim.rise * rim.side),
                                       halfAngle: Double.pi / 4))
                (capV, wallV) = (inset * 2.0.squareRoot(), rim.radius * 2.0.squareRoot())
            }
            let (lowV, highV) = (min(capV, wallV), max(capV, wallV))
            for (arcIndex, arc) in rim.arcs.enumerated() {
                guard let edge = model.edges[arc.edgeID], let a = model.vertices[edge.startVertexID]?.point,
                      let b = model.vertices[edge.endVertexID]?.point else {
                    throw TopologyError.missingReference("Missing rim arc.")
                }
                func onCap(_ p: Point3D) -> Point3D { rim.center + (p - rim.center) * ((rim.radius - rim.side * r) / rim.radius) }
                func onWall(_ p: Point3D) -> Point3D { p + n * (rim.rise * r) }
                capMoves[rim.capFaceID, default: []] += [(a, onCap(a)), (b, onCap(b))]
                wallMoves[arc.cylinderFaceID, default: []] += [(a, onWall(a)), (b, onWall(b))]
                let rimCircle = Circle3D(center: rim.center, normal: rim.circleNormal, radius: rim.radius)
                arcMoves[rim.capFaceID, default: []].append((rimCircle, capCircle))
                arcMoves[arc.cylinderFaceID, default: []].append((rimCircle, wallCircle))
                var (u0, u1) = (try band.parameterProjection(of: onCap(a), tolerance: tolerance).u,
                                try band.parameterProjection(of: onCap(b), tolerance: tolerance).u)
                u1 = nearestTurn(from: u0, to: u1)
                if u1 < u0 { swap(&u0, &u1) }
                let parents = selectedParent[arc.edgeID].map { [$0] } ?? context.subshapeIDs(for: .edge(arc.edgeID))
                let stableID = "rim:\(rimIndex):\(arcIndex)"
                func point(_ u: Double, _ v: Double) throws -> Point3D { try band.point(u: u, v: v, tolerance: tolerance) }
                /// The circle `curve` from (u, v) to (u, v) on the band, with its pcurve there.
                func arcEdge(_ name: String, _ curve: Circle3D, from start: (u: Double, v: Double), to end: (u: Double, v: Double),
                             _ pcurve: SurfaceParameterCurve) throws -> BRepSewingEdge {
                    let (p, q) = (try point(start.u, start.v), try point(end.u, end.v))
                    let (t0, t1) = try parameters(curve, from: p, to: q)
                    return BRepSewingEdge(stableID: "\(stableID):\(name)", curve: .circle(curve), startParameter: t0, endParameter: t1,
                                          startPoint: p, endPoint: q, surfaceParameterCurve: pcurve, parentSubshapeIDs: parents)
                }
                /// The band's section at `u` from `v0` to `v1`: the tube's quarter circle, or the cone's line.
                func sectionEdge(_ name: String, at u: Double, from v0: Double, to v1: Double) throws -> BRepSewingEdge {
                    let (p, q) = (try point(u, v0), try point(u, v1))
                    let pcurve = SurfaceParameterCurve.constantU(u: u, vStart: v0, vEnd: v1)
                    switch shape {
                    case .round:
                        let tubeCenter = try point(u, capV) + n * (rim.rise * r)
                        let radial = try (tubeCenter - wallCenter).normalized(tolerance: tolerance.distance)
                        return try arcEdge(name, Circle3D(center: tubeCenter, normal: n.cross(radial), radius: r), from: (u, v0), to: (u, v1), pcurve)
                    case .chamfer:
                        let delta = q - p
                        return BRepSewingEdge(stableID: "\(stableID):\(name)",
                                              curve: .line(Line3D(origin: p, direction: try delta.normalized(tolerance: tolerance.distance))),
                                              startParameter: 0, endParameter: delta.length, startPoint: p, endPoint: q,
                                              surfaceParameterCurve: pcurve, parentSubshapeIDs: parents)
                    }
                }
                let lowCircle = lowV == capV ? capCircle : wallCircle, highCircle = highV == capV ? capCircle : wallCircle
                let edges = [
                    try arcEdge("low", lowCircle, from: (u0, lowV), to: (u1, lowV), .constantV(v: lowV, uStart: u0, uEnd: u1)),
                    try sectionEdge("end", at: u1, from: lowV, to: highV),
                    try arcEdge("high", highCircle, from: (u1, highV), to: (u0, highV), .constantV(v: highV, uStart: u1, uEnd: u0)),
                    try sectionEdge("start", at: u0, from: highV, to: lowV),
                ]
                // The band faces away from the material: toward the corner it cuts off, or away
                // from the corner it fills.
                let (middleU, middleV) = ((u0 + u1) / 2, (lowV + highV) / 2)
                let middle = try point(middleU, middleV)
                let capContact = try point(middleU, capV)
                let rimPoint = rim.center + (capContact - rim.center) * (rim.radius / (rim.radius - rim.side * r))
                let facing = try band.normal(u: middleU, v: middleV, tolerance: tolerance).dot(rimPoint - middle) * -rim.rise >= 0
                let loop = facing ? edges : try edges.reversed().map(reversed)
                patches.append(BRepSewingFacePatch(stableID: stableID, surface: band, orientation: facing ? .forward : .reversed,
                                                   loops: [BRepSewingLoop(stableID: "\(stableID):outer", role: .outer, edges: loop)],
                                                   parentSubshapeIDs: [rim.capFaceID, arc.cylinderFaceID].flatMap { context.subshapeIDs(for: .face($0)) }))
            }
        }
        // Every face beside a rim with its rim arcs moved and the straight edges reaching them
        // shortened; every other face as it was.
        for (faceIndex, faceID) in shell.faceIDs.enumerated() {
            let source = try SourceBRepFacePatchBuilder().build(faceID: faceID, stableID: "source-face:\(faceIndex)", from: model,
                                                                sourceSubshapes: context.subshapes.entries, tolerance: tolerance).patch
            let moves = (capMoves[faceID] ?? []) + (wallMoves[faceID] ?? [])
            guard moves.isEmpty == false else {
                patches.append(source)
                continue
            }
            let circleMoves = arcMoves[faceID] ?? []
            func moved(_ point: Point3D) -> Point3D? {
                moves.first { $0.from.isApproximatelyEqual(to: point, tolerance: tolerance.distance) }?.to
            }
            let loops = try source.loops.map { loop in
                BRepSewingLoop(stableID: loop.stableID, role: loop.role, edges: try loop.edges.map { edge in
                    let (start, end) = (moved(edge.startPoint), moved(edge.endPoint))
                    guard start != nil || end != nil else { return edge }
                    let (p, q) = (start ?? edge.startPoint, end ?? edge.endPoint)
                    if case let .circle(original) = edge.curve, start != nil, end != nil,
                       let target = circleMoves.first(where: { same(original, $0.from) })?.to {
                        let (t0, t1) = try parameters(target, from: p, to: q)
                        return BRepSewingEdge(stableID: edge.stableID, curve: .circle(target), startParameter: t0, endParameter: t1,
                                              startPoint: p, endPoint: q,
                                              surfaceParameterCurve: try circlePcurve(target, from: t0, to: t1, on: source.surface),
                                              parentSubshapeIDs: edge.parentSubshapeIDs,
                                              startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                                              endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs)
                    }
                    guard case .line = edge.curve else {
                        throw refuse("A rim's vertices end straight edges of its faces.")
                    }
                    let delta = q - p
                    guard delta.dot(edge.endPoint - edge.startPoint) > tolerance.distance * delta.length else {
                        throw KernelError(phase: .evaluation, code: .topologyFailure, featureID: featureID, tolerance: tolerance,
                                          message: "A rim's round removes an edge beside it.")
                    }
                    let (pu, qu) = (try source.surface.parameterProjection(of: p, tolerance: tolerance),
                                    try source.surface.parameterProjection(of: q, tolerance: tolerance))
                    return BRepSewingEdge(stableID: edge.stableID,
                                          curve: .line(Line3D(origin: p, direction: try delta.normalized(tolerance: tolerance.distance))),
                                          startParameter: 0, endParameter: delta.length, startPoint: p, endPoint: q,
                                          surfaceParameterCurve: .polyline([SurfaceParameter(u: pu.u, v: pu.v),
                                                                            SurfaceParameter(u: qu.u, v: qu.v)]),
                                          parentSubshapeIDs: edge.parentSubshapeIDs,
                                          startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                                          endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs)
                })
            }
            patches.append(BRepSewingFacePatch(stableID: source.stableID, surface: source.surface, orientation: source.orientation,
                                               loops: loops, parentSubshapeIDs: source.parentSubshapeIDs))
        }
        return BRepSewingRequest(featureID: featureID, bodyKind: .solid,
                                 shells: [BRepSewingShell(stableID: "shell:0", patches: patches)],
                                 bodyParentSubshapeIDs: context.subshapeIDs(for: .body(bodyID)))
    }

    /// Whether two circles are one: the same centre, radius and axis (either way along it).
    private func same(_ a: Circle3D, _ b: Circle3D) -> Bool {
        a.center.isApproximatelyEqual(to: b.center, tolerance: tolerance.distance)
            && abs(a.radius - b.radius) <= tolerance.distance
            && a.normal.cross(b.normal).length <= tolerance.angle * max(a.normal.length * b.normal.length, 1)
    }

    /// −1 when the wall's vertices all lie below the cap's plane through `center` (against its
    /// outward normal `cap`), +1 when all lie above it, some strictly; 0 when it crosses the plane.
    private func wallSide(_ wall: FaceID, cap: Vector3D, at center: Point3D, model: BRepModel) throws -> Double {
        guard let face = model.faces[wall] else { throw TopologyError.missingReference("Missing rim wall.") }
        let heights = try face.loops.flatMap { loopID -> [Double] in
            guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("Missing rim wall loop.") }
            return try loop.edges.flatMap { use -> [Double] in
                guard let edge = model.edges[use.edgeID], let start = model.vertices[edge.startVertexID]?.point,
                      let end = model.vertices[edge.endVertexID]?.point else {
                    throw TopologyError.missingReference("Missing rim wall edge.")
                }
                return [(start - center).dot(cap), (end - center).dot(cap)]
            }
        }
        if heights.allSatisfy({ $0 <= tolerance.distance }), heights.contains(where: { $0 < -tolerance.distance }) { return -1 }
        if heights.allSatisfy({ $0 >= -tolerance.distance }), heights.contains(where: { $0 > tolerance.distance }) { return 1 }
        return 0
    }

    private func midParameter(_ circle: Circle3D, _ start: Point3D, _ end: Point3D) throws -> Double {
        let curve = Curve3D.circle(circle)
        let t0 = try curve.parameterProjection(of: start, tolerance: tolerance).parameter
        let t1 = nearestTurn(from: t0, to: try curve.parameterProjection(of: end, tolerance: tolerance).parameter)
        return (t0 + t1) / 2
    }

    private func arcSpan(_ circle: Circle3D, _ start: Point3D, _ end: Point3D) throws -> Double {
        let curve = Curve3D.circle(circle)
        let t0 = try curve.parameterProjection(of: start, tolerance: tolerance).parameter
        var t1 = try curve.parameterProjection(of: end, tolerance: tolerance).parameter
        if start.isApproximatelyEqual(to: end, tolerance: tolerance.distance) { return 2 * Double.pi }
        t1 = nearestTurn(from: t0, to: t1)
        return t1 - t0
    }

    /// `circle`'s parameters at `start` and `end`, over the shorter way between them: a rim's arcs
    /// each turn less than half way round, and a moved arc keeps its circle's normal.
    private func parameters(_ circle: Circle3D, from start: Point3D, to end: Point3D) throws -> (Double, Double) {
        let curve = Curve3D.circle(circle)
        let t0 = try curve.parameterProjection(of: start, tolerance: tolerance).parameter
        return (t0, nearestTurn(from: t0, to: try curve.parameterProjection(of: end, tolerance: tolerance).parameter))
    }

    /// The pcurve of `circle` from `t0` to `t1` on a plane (its harmonic image) or on a coaxial
    /// cylinder (a line of constant height).
    private func circlePcurve(_ circle: Circle3D, from t0: Double, to t1: Double, on surface: Surface3D) throws -> SurfaceParameterCurve {
        let curve = Curve3D.circle(circle)
        let p = try curve.point(at: t0, tolerance: tolerance)
        switch surface {
        case .plane, .analytic(.plane):
            let center = try surface.parameterProjection(of: circle.center, tolerance: tolerance)
            let cosine = try surface.parameterProjection(of: curve.point(at: 0, tolerance: tolerance), tolerance: tolerance)
            let sine = try surface.parameterProjection(of: curve.point(at: Double.pi / 2, tolerance: tolerance), tolerance: tolerance)
            return .harmonic(center: Point2D(x: center.u, y: center.v), cosine: Point2D(x: cosine.u - center.u, y: cosine.v - center.v),
                             sine: Point2D(x: sine.u - center.u, y: sine.v - center.v), startParameter: t0, endParameter: t1)
        default:
            // On the coaxial cylinder the circle is a line of constant height, turning in u as far
            // as it turns, the way its middle lies.
            let pu = try surface.parameterProjection(of: p, tolerance: tolerance)
            let middle = try surface.parameterProjection(of: curve.point(at: (t0 + t1) / 2, tolerance: tolerance), tolerance: tolerance)
            let sense: Double = nearestTurn(from: pu.u, to: middle.u) >= pu.u ? 1 : -1
            return .constantV(v: pu.v, uStart: pu.u, uEnd: pu.u + sense * abs(t1 - t0))
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

    /// `end` shifted by whole turns to lie within half a turn of `start`.
    private func nearestTurn(from start: Double, to end: Double) -> Double {
        var delta = (end - start).truncatingRemainder(dividingBy: 2 * Double.pi)
        if delta > Double.pi { delta -= 2 * Double.pi }
        if delta < -Double.pi { delta += 2 * Double.pi }
        return start + delta
    }
}
