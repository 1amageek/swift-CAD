import Foundation
import CADCore
import CADGeometry
import CADTopology

/// A round or chamfer along a whole tangent loop of a planar cap: a closed loop of lines and
/// circular arcs, tangent where they meet (a cylinder's rim, a rounded rectangle's or a slot's
/// outline, a hole's), each between the cap and a wall square to it — a plane through a line, the
/// coaxial cylinder through an arc — the walls all running down from the cap (a convex loop, the
/// band cutting the corner away) or all rising from it (a concave one, a boss's base or a blind
/// hole's floor, the band filling the corner). The band is the round's tube or the chamfer's 45°
/// line swept along the loop: a cylinder or a plane along a line, a torus or a cone along an arc,
/// meeting its neighbours on the section at their tangent joint. The cap's loop moves the distance
/// into the cap and each wall's edge the distance along the wall. A selected edge of such a loop
/// takes the whole loop, as a tangent chain does.
package struct CapLoopBlendBuilder {
    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// The band's cross-section: a round's quarter circle or a chamfer's line, each `distance`
    /// along the cap and along the wall.
    package enum Section: Sendable {
        case round(Double)
        case chamfer(Double)

        var distance: Double {
            switch self {
            case let .round(distance), let .chamfer(distance): distance
            }
        }
    }

    /// One edge of a cap loop as the loop runs: its ends in that order, its circle when it is an
    /// arc (with the parameters it runs over), and the wall on its other side.
    private struct Segment {
        let edgeID: EdgeID
        let wallFaceID: FaceID
        let start: Point3D
        let end: Point3D
        let arc: (circle: Circle3D, from: Double, to: Double)?
    }

    /// A cap loop: the cap, its outward normal, whether the walls rise (+1) or fall (−1) from it,
    /// its segments in order, and the sense (+1 or −1) that turns `normal × tangent` into the cap.
    private struct CapLoop {
        let capFaceID: FaceID
        let normal: Vector3D
        let rise: Double
        let segments: [Segment]
        let inwardSense: Double
    }

    /// Whether every edge of `edgeIDs` lies on a tangent loop of lines and arcs, holding an arc, of
    /// a planar face: the loops this builder takes, which straight blends do not.
    package func admits(_ edgeIDs: [EdgeID], model: BRepModel) throws -> Bool {
        guard edgeIDs.isEmpty == false else { return false }
        for edgeID in edgeIDs where try capLoopID(containing: edgeID, model: model) == nil {
            return false
        }
        return true
    }

    package func request(featureID: FeatureID, bodyID: BodyID, selected: [(edgeID: EdgeID, subshapeID: SubshapeID)],
                         section shape: Section, context: EvaluationContext) throws -> BRepSewingRequest {
        let d = shape.distance
        let model = context.brep
        func refuse(_ message: String) -> KernelError {
            KernelError(phase: .evaluation, code: .unsupportedCapability, featureID: featureID, tolerance: tolerance, message: message)
        }
        guard let body = model.bodies[bodyID], body.kind == .solid, body.shellIDs.count == 1,
              let shell = model.shells[body.shellIDs[0]] else {
            throw refuse("A cap loop is blended on one single-shell solid.")
        }
        // Every loop the selection touches.
        var loops: [CapLoop] = []
        var seen: Set<LoopID> = []
        for selection in selected {
            guard let (capFaceID, loopID) = try capLoopID(containing: selection.edgeID, model: model) else {
                throw refuse("A blended loop is a tangent loop of lines and arcs on a planar cap.")
            }
            guard seen.insert(loopID).inserted else { continue }
            loops.append(try capLoop(capFaceID: capFaceID, loopID: loopID, shell: shell, model: model, featureID: featureID))
        }
        let selectedParent = Dictionary(selected.map { ($0.edgeID, $0.subshapeID) }, uniquingKeysWith: { first, _ in first })
        var patches: [BRepSewingFacePatch] = []
        // Where each loop vertex lands on its cap and on its walls, and the segments each face's
        // edges move to.
        var vertexMoves: [FaceID: [(from: Point3D, to: Point3D)]] = [:]
        var segmentMoves: [FaceID: [(from: Segment, to: Segment)]] = [:]
        for (loopIndex, loop) in loops.enumerated() {
            let n = loop.normal
            let wall = n * loop.rise
            func inward(_ segment: Segment, at point: Point3D) throws -> Vector3D {
                let tangent: Vector3D
                if let arc = segment.arc {
                    let radial = try (point - arc.circle.center).normalized(tolerance: tolerance.distance)
                    tangent = arc.circle.normal.cross(radial) * (arc.to >= arc.from ? 1 : -1)
                } else {
                    tangent = segment.end - segment.start
                }
                return try n.cross(tangent).normalized(tolerance: tolerance.distance) * loop.inwardSense
            }
            for (index, segment) in loop.segments.enumerated() {
                let parents = selectedParent[segment.edgeID].map { [$0] } ?? context.subshapeIDs(for: .edge(segment.edgeID))
                let stableID = "loop:\(loopIndex):\(index)"
                let (mStart, mEnd) = (try inward(segment, at: segment.start), try inward(segment, at: segment.end))
                let capSegment: Segment
                let wallSegment: Segment
                if let arc = segment.arc {
                    let capRadius = (segment.start + mStart * d - arc.circle.center).length
                    capSegment = Segment(edgeID: segment.edgeID, wallFaceID: segment.wallFaceID, start: segment.start + mStart * d,
                                         end: segment.end + mEnd * d,
                                         arc: (Circle3D(center: arc.circle.center, normal: arc.circle.normal, radius: capRadius), arc.from, arc.to))
                    wallSegment = Segment(edgeID: segment.edgeID, wallFaceID: segment.wallFaceID, start: segment.start + wall * d,
                                          end: segment.end + wall * d,
                                          arc: (Circle3D(center: arc.circle.center + wall * d, normal: arc.circle.normal,
                                                         radius: arc.circle.radius), arc.from, arc.to))
                } else {
                    capSegment = Segment(edgeID: segment.edgeID, wallFaceID: segment.wallFaceID, start: segment.start + mStart * d,
                                         end: segment.end + mEnd * d, arc: nil)
                    wallSegment = Segment(edgeID: segment.edgeID, wallFaceID: segment.wallFaceID, start: segment.start + wall * d,
                                          end: segment.end + wall * d, arc: nil)
                }
                vertexMoves[loop.capFaceID, default: []] += [(segment.start, capSegment.start), (segment.end, capSegment.end)]
                vertexMoves[segment.wallFaceID, default: []] += [(segment.start, wallSegment.start), (segment.end, wallSegment.end)]
                segmentMoves[loop.capFaceID, default: []].append((segment, capSegment))
                segmentMoves[segment.wallFaceID, default: []].append((segment, wallSegment))
                patches.append(try bandPatch(stableID: stableID, shape: shape, segment: segment, cap: capSegment, wall: wallSegment,
                                             inward: (mStart, mEnd), inwardAt: { try inward(segment, at: $0) },
                                             normal: n, rise: loop.rise, parents: parents,
                                             faceParents: [loop.capFaceID, segment.wallFaceID].flatMap { context.subshapeIDs(for: .face($0)) }))
            }
        }
        // Every face beside a loop with its loop edges moved and the straight edges reaching them
        // shortened; every other face as it was.
        for (faceIndex, faceID) in shell.faceIDs.enumerated() {
            let source = try SourceBRepFacePatchBuilder().build(faceID: faceID, stableID: "source-face:\(faceIndex)", from: model,
                                                                sourceSubshapes: context.subshapes.entries, tolerance: tolerance).patch
            let moves = vertexMoves[faceID] ?? []
            guard moves.isEmpty == false else {
                patches.append(source)
                continue
            }
            let segments = segmentMoves[faceID] ?? []
            func moved(_ point: Point3D) -> Point3D? {
                moves.first { $0.from.isApproximatelyEqual(to: point, tolerance: tolerance.distance) }?.to
            }
            func matches(_ edge: BRepSewingEdge, _ segment: Segment) -> Bool {
                (edge.startPoint.isApproximatelyEqual(to: segment.start, tolerance: tolerance.distance)
                    && edge.endPoint.isApproximatelyEqual(to: segment.end, tolerance: tolerance.distance))
                    || (edge.startPoint.isApproximatelyEqual(to: segment.end, tolerance: tolerance.distance)
                        && edge.endPoint.isApproximatelyEqual(to: segment.start, tolerance: tolerance.distance))
            }
            let loops = try source.loops.map { loop in
                BRepSewingLoop(stableID: loop.stableID, role: loop.role, edges: try loop.edges.map { edge in
                    let (start, end) = (moved(edge.startPoint), moved(edge.endPoint))
                    guard start != nil || end != nil else { return edge }
                    let (p, q) = (start ?? edge.startPoint, end ?? edge.endPoint)
                    // A loop segment becomes its moved segment, run the way the edge runs.
                    if let move = segments.first(where: { matches(edge, $0.from) }), let arc = move.to.arc {
                        let forward = edge.startPoint.isApproximatelyEqual(to: move.from.start, tolerance: tolerance.distance)
                        let (t0, t1) = forward ? (arc.from, arc.to) : (arc.to, arc.from)
                        return BRepSewingEdge(stableID: edge.stableID, curve: .circle(arc.circle), startParameter: t0, endParameter: t1,
                                              startPoint: p, endPoint: q,
                                              surfaceParameterCurve: try circlePcurve(arc.circle, from: t0, to: t1, on: source.surface),
                                              parentSubshapeIDs: edge.parentSubshapeIDs,
                                              startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                                              endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs)
                    }
                    guard case .line = edge.curve else {
                        throw refuse("A blended loop's vertices end straight edges of its faces.")
                    }
                    let delta = q - p
                    guard delta.dot(edge.endPoint - edge.startPoint) > tolerance.distance * delta.length else {
                        throw KernelError(phase: .evaluation, code: .topologyFailure, featureID: featureID, tolerance: tolerance,
                                          message: "A loop's blend removes an edge beside it.")
                    }
                    return BRepSewingEdge(stableID: edge.stableID,
                                          curve: .line(Line3D(origin: p, direction: try delta.normalized(tolerance: tolerance.distance))),
                                          startParameter: 0, endParameter: delta.length, startPoint: p, endPoint: q,
                                          surfaceParameterCurve: try linePcurve(from: p, to: q, on: source.surface),
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

    // MARK: - The band

    /// One segment's band from its section at the start to its section at the end: a round's
    /// cylinder or torus, a chamfer's plane or cone, bounded by the cap contact `cap`, the wall
    /// contact `wall` and the two sections, facing away from the material.
    private func bandPatch(stableID: String, shape: Section, segment: Segment, cap: Segment, wall: Segment,
                           inward: (start: Vector3D, end: Vector3D), inwardAt: (Point3D) throws -> Vector3D,
                           normal n: Vector3D, rise: Double,
                           parents: [SubshapeID], faceParents: [SubshapeID]) throws -> BRepSewingFacePatch {
        let d = shape.distance
        let wallDirection = n * rise
        /// The section at a loop point: from the cap contact to the wall contact.
        func sectionEdge(_ name: String, at point: Point3D, inward m: Vector3D, tangent: Vector3D, reversed: Bool) throws -> BRepSewingEdge {
            let (capPoint, wallPoint) = (point + m * d, point + wallDirection * d)
            let (p, q) = reversed ? (wallPoint, capPoint) : (capPoint, wallPoint)
            switch shape {
            case .round:
                let circle = Circle3D(center: point + (m + wallDirection) * d, normal: tangent, radius: d)
                let (t0, t1) = try shortParameters(circle, from: p, to: q)
                return BRepSewingEdge(stableID: "\(stableID):\(name)", curve: .circle(circle), startParameter: t0, endParameter: t1,
                                      startPoint: p, endPoint: q, surfaceParameterCurve: .polyline([]), parentSubshapeIDs: parents)
            case .chamfer:
                let delta = q - p
                return BRepSewingEdge(stableID: "\(stableID):\(name)",
                                      curve: .line(Line3D(origin: p, direction: try delta.normalized(tolerance: tolerance.distance))),
                                      startParameter: 0, endParameter: delta.length, startPoint: p, endPoint: q,
                                      surfaceParameterCurve: .polyline([]), parentSubshapeIDs: parents)
            }
        }
        let surface: Surface3D
        if let arc = segment.arc {
            let center = arc.circle.center
            let axisNormal = try arc.circle.normal.normalized(tolerance: tolerance.distance)
            let capRadius = (cap.start - center).length
            switch shape {
            case .round:
                surface = .analytic(.torus(center: center + wallDirection * d, axis: axisNormal, majorRadius: capRadius, minorRadius: d))
            case .chamfer:
                // The 45° line from the cap's contact to the wall's meets the axis at the apex.
                let outward = arc.circle.radius > capRadius ? 1.0 : -1.0
                let apexHeight = -rise * outward * capRadius
                let axisDirection = n * (rise * outward)
                surface = .analytic(.cone(apex: center + n * apexHeight, axis: axisDirection, halfAngle: Double.pi / 4))
            }
        } else {
            let along = try (segment.end - segment.start).normalized(tolerance: tolerance.distance)
            switch shape {
            case .round:
                surface = .cylinder(Cylinder3D(origin: segment.start + (inward.start + wallDirection) * d, axis: along, radius: d))
            case .chamfer:
                let across = cap.start - wall.start
                let planeNormal = try along.cross(across).normalized(tolerance: tolerance.distance)
                surface = .plane(Plane3D(origin: cap.start, normal: planeNormal))
            }
        }
        // Tangents at the segment's ends, along the loop.
        func tangent(at point: Point3D) throws -> Vector3D {
            if let arc = segment.arc {
                let radial = try (point - arc.circle.center).normalized(tolerance: tolerance.distance)
                return try (arc.circle.normal.cross(radial) * (arc.to >= arc.from ? 1 : -1)).normalized(tolerance: tolerance.distance)
            }
            return try (segment.end - segment.start).normalized(tolerance: tolerance.distance)
        }
        // The loop: cap contact forward, the end's section to the wall, wall contact back, the start's
        // section up to the cap; pcurves from the band's own parameters.
        var edges = [
            try contactEdge("\(stableID):cap", cap, forward: true, parents: parents),
            try sectionEdge("end", at: segment.end, inward: inward.end, tangent: try tangent(at: segment.end), reversed: false),
            try contactEdge("\(stableID):wall", wall, forward: false, parents: parents),
            try sectionEdge("start", at: segment.start, inward: inward.start, tangent: try tangent(at: segment.start), reversed: true),
        ]
        edges = try chainedPcurves(edges, on: surface)
        // Facing away from the material: toward the corner a convex band cuts off, away from the
        // corner a concave one fills; judged at the segment's middle, where the band runs at 45°.
        let corner: Point3D
        if let arc = segment.arc {
            corner = try Curve3D.circle(arc.circle).point(at: (arc.from + arc.to) / 2, tolerance: tolerance)
        } else {
            corner = segment.start + (segment.end - segment.start) * 0.5
        }
        let reach: Double
        switch shape {
        case .round: reach = d * (1 - 0.5.squareRoot())
        case .chamfer: reach = d / 2
        }
        let bandPoint = corner + (try inwardAt(corner) + wallDirection) * reach
        let uv = try surface.parameterProjection(of: bandPoint, tolerance: tolerance)
        let facing = try surface.normal(u: uv.u, v: uv.v, tolerance: tolerance).dot(corner - bandPoint) * -rise >= 0
        let loopEdges = try orientedLoop(edges, on: surface, facing: facing)
        return BRepSewingFacePatch(stableID: stableID, surface: surface, orientation: facing ? .forward : .reversed,
                                   loops: [BRepSewingLoop(stableID: "\(stableID):outer", role: .outer, edges: loopEdges)],
                                   parentSubshapeIDs: faceParents)
    }

    /// A contact segment as an edge, run forward or back.
    private func contactEdge(_ stableID: String, _ segment: Segment, forward: Bool, parents: [SubshapeID]) throws -> BRepSewingEdge {
        let (p, q) = forward ? (segment.start, segment.end) : (segment.end, segment.start)
        if let arc = segment.arc {
            let (t0, t1) = forward ? (arc.from, arc.to) : (arc.to, arc.from)
            return BRepSewingEdge(stableID: stableID, curve: .circle(arc.circle), startParameter: t0, endParameter: t1,
                                  startPoint: p, endPoint: q, surfaceParameterCurve: .polyline([]), parentSubshapeIDs: parents)
        }
        let delta = q - p
        return BRepSewingEdge(stableID: stableID, curve: .line(Line3D(origin: p, direction: try delta.normalized(tolerance: tolerance.distance))),
                              startParameter: 0, endParameter: delta.length, startPoint: p, endPoint: q,
                              surfaceParameterCurve: .polyline([]), parentSubshapeIDs: parents)
    }

    /// `edges` (a closed chain) with their pcurves on the band: each the band's isoparametric line
    /// (a contact or a section), straight in its parameters, each periodic coordinate carried on
    /// from the previous edge's end through the edge's middle, so the chain closes in the plane of
    /// parameters as it does on the band.
    private func chainedPcurves(_ edges: [BRepSewingEdge], on surface: Surface3D) throws -> [BRepSewingEdge] {
        let (uPeriodic, vPeriodic): (Bool, Bool)
        switch surface {
        case .analytic(.torus): (uPeriodic, vPeriodic) = (true, true)
        case .analytic(.cone), .cylinder, .analytic(.cylinder): (uPeriodic, vPeriodic) = (true, false)
        default: (uPeriodic, vPeriodic) = (false, false)
        }
        func carried(_ from: Double, to value: Double, periodic: Bool) -> Double {
            periodic ? nearestTurn(from: from, to: value) : value
        }
        var previous: SurfaceParameter?
        return try edges.map { edge in
            let raw = try surface.parameterProjection(of: edge.startPoint, tolerance: tolerance)
            let start = previous.map { SurfaceParameter(u: carried($0.u, to: raw.u, periodic: uPeriodic),
                                                        v: carried($0.v, to: raw.v, periodic: vPeriodic)) }
                ?? SurfaceParameter(u: raw.u, v: raw.v)
            let middlePoint = try edge.curve.point(at: (edge.startParameter + edge.endParameter) / 2, tolerance: tolerance)
            let middleRaw = try surface.parameterProjection(of: middlePoint, tolerance: tolerance)
            let middle = SurfaceParameter(u: carried(start.u, to: middleRaw.u, periodic: uPeriodic),
                                          v: carried(start.v, to: middleRaw.v, periodic: vPeriodic))
            let endRaw = try surface.parameterProjection(of: edge.endPoint, tolerance: tolerance)
            let end = SurfaceParameter(u: carried(middle.u, to: endRaw.u, periodic: uPeriodic),
                                       v: carried(middle.v, to: endRaw.v, periodic: vPeriodic))
            previous = end
            let pcurve: SurfaceParameterCurve
            if abs(end.u - start.u) <= tolerance.angle {
                pcurve = .constantU(u: start.u, vStart: start.v, vEnd: end.v)
            } else if abs(end.v - start.v) <= tolerance.angle {
                pcurve = .constantV(v: start.v, uStart: start.u, uEnd: end.u)
            } else {
                pcurve = .polyline([start, end])
            }
            return BRepSewingEdge(stableID: edge.stableID, curve: edge.curve, startParameter: edge.startParameter,
                                  endParameter: edge.endParameter, startPoint: edge.startPoint, endPoint: edge.endPoint,
                                  surfaceParameterCurve: pcurve, parentSubshapeIDs: edge.parentSubshapeIDs)
        }
    }

    /// `edges` as the band's loop: counterclockwise in its parameters about its own normal when
    /// `facing`, otherwise run back.
    private func orientedLoop(_ edges: [BRepSewingEdge], on surface: Surface3D, facing: Bool) throws -> [BRepSewingEdge] {
        // The loop's signed area in the parameter plane, from its pcurves' ends.
        var area = 0.0
        for edge in edges {
            let (a, b) = try ends(of: edge.surfaceParameterCurve)
            area += a.u * b.v - b.u * a.v
        }
        let counterclockwise = area > 0
        return counterclockwise == facing ? edges : try edges.reversed().map(reversed)
    }

    private func ends(of pcurve: SurfaceParameterCurve) throws -> (SurfaceParameter, SurfaceParameter) {
        switch pcurve {
        case let .constantU(u, v0, v1): return (SurfaceParameter(u: u, v: v0), SurfaceParameter(u: u, v: v1))
        case let .constantV(v, u0, u1): return (SurfaceParameter(u: u0, v: v), SurfaceParameter(u: u1, v: v))
        case let .polyline(points) where points.count >= 2: return (points[0], points[points.count - 1])
        default: throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: tolerance, message: "A band's pcurve is straight.")
        }
    }

    // MARK: - Finding the loop

    /// The planar face and its loop holding `edgeID` when that loop is a tangent loop of lines and
    /// arcs with at least one arc; nil otherwise.
    private func capLoopID(containing edgeID: EdgeID, model: BRepModel) throws -> (FaceID, LoopID)? {
        for (faceID, face) in model.faces.sorted(by: { $0.key < $1.key }) {
            guard case .plane? = model.geometry.surfaces[face.surfaceID] else { continue }
            for loopID in face.loops {
                guard let loop = model.loops[loopID], loop.edges.contains(where: { $0.edgeID == edgeID }) else { continue }
                let curves = loop.edges.compactMap { use in model.edges[use.edgeID].flatMap { model.geometry.curves[$0.curveID] } }
                guard curves.count == loop.edges.count,
                      curves.allSatisfy({ curve in
                          switch curve { case .line, .circle: return true; default: return false }
                      }),
                      curves.contains(where: { if case .circle = $0 { return true } else { return false } }) else { continue }
                let runs = try loop.edges.map { try run(of: $0, model: model) }
                let tangentAtJoints = zip(runs, runs.dropFirst() + runs.prefix(1)).allSatisfy { before, after in
                    before.endTangent.cross(after.startTangent).length <= 1e-7 && before.endTangent.dot(after.startTangent) > 0
                }
                if tangentAtJoints { return (faceID, loopID) }
            }
        }
        return nil
    }

    /// A coedge's ends as the loop runs it, its unit tangents there, and its circle's parameters.
    private func run(of use: Coedge, model: BRepModel) throws -> (start: Point3D, end: Point3D, startTangent: Vector3D,
                                                                  endTangent: Vector3D, arc: (circle: Circle3D, from: Double, to: Double)?) {
        guard let edge = model.edges[use.edgeID], let curve = model.geometry.curves[edge.curveID],
              let a = model.vertices[edge.startVertexID]?.point, let b = model.vertices[edge.endVertexID]?.point else {
            throw TopologyError.missingReference("Missing loop edge.")
        }
        let forward = use.orientation == .forward
        let (start, end) = forward ? (a, b) : (b, a)
        if case let .circle(circle) = curve {
            guard a.isApproximatelyEqual(to: b, tolerance: tolerance.distance) == false else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): a loop of one closed circular edge needs its
                // band split along a seam, which is not built, so it is refused. Production path:
                // CapLoopBlendBuilder from Fillet and Chamfer. Complete only when closed rims
                // blend, verified by a revolved disc's rim.
                throw KernelError(phase: .evaluation, code: .unsupportedCapability, tolerance: tolerance,
                                  message: "A blended loop's arcs each turn less than all the way round.")
            }
            // The edge's own interval, or the shorter way between its ends.
            let t0 = try curve.parameterProjection(of: a, tolerance: tolerance).parameter
            var t1 = try curve.parameterProjection(of: b, tolerance: tolerance).parameter
            if let trim = edge.trim {
                t1 = t0 + (trim.endParameter - trim.startParameter)
            } else {
                t1 = nearestTurn(from: t0, to: t1)
            }
            let (from, to) = forward ? (t0, t1) : (t1, t0)
            func tangent(_ point: Point3D) throws -> Vector3D {
                let radial = try (point - circle.center).normalized(tolerance: tolerance.distance)
                return try (circle.normal.cross(radial) * (to >= from ? 1 : -1)).normalized(tolerance: tolerance.distance)
            }
            return (start, end, try tangent(start), try tangent(end), (circle, from, to))
        }
        let direction = try (end - start).normalized(tolerance: tolerance.distance)
        return (start, end, direction, direction, nil)
    }

    /// The loop with its walls, checked: each segment's other face a wall square to the cap (a
    /// plane through a line, the coaxial cylinder through an arc), the walls all on one side.
    private func capLoop(capFaceID: FaceID, loopID: LoopID, shell: Shell, model: BRepModel, featureID: FeatureID) throws -> CapLoop {
        func refuse(_ message: String) -> KernelError {
            KernelError(phase: .evaluation, code: .unsupportedCapability, featureID: featureID, tolerance: tolerance, message: message)
        }
        guard let capFace = model.faces[capFaceID], case let .plane(plane)? = model.geometry.surfaces[capFace.surfaceID],
              let loop = model.loops[loopID] else {
            throw TopologyError.missingReference("Missing cap.")
        }
        let normal = try (capFace.orientation == .forward ? plane.normal : plane.normal * -1).normalized(tolerance: tolerance.distance)
        var segments: [Segment] = []
        var rise = 0.0
        var samples: [Point3D] = []
        for use in loop.edges {
            let run = try run(of: use, model: model)
            let walls = try shell.faceIDs.filter { faceID in
                guard faceID != capFaceID, let face = model.faces[faceID] else { return false }
                return try face.loops.contains { id in
                    guard let other = model.loops[id] else { throw TopologyError.missingReference("Missing loop.") }
                    return other.edges.contains { $0.edgeID == use.edgeID }
                }
            }
            guard walls.count == 1, let wallFace = model.faces[walls[0]], let wallSurface = model.geometry.surfaces[wallFace.surfaceID] else {
                throw refuse("A blended loop's edges each bound the cap and one wall.")
            }
            // The wall square to the cap: a plane holding the cap's normal, or the arc's coaxial cylinder.
            switch (wallSurface, run.arc) {
            case let (.plane(wallPlane), nil):
                guard abs(wallPlane.normal.dot(normal)) <= tolerance.angle * max(wallPlane.normal.length, 1) else {
                    throw refuse("A blended loop's walls are square to its cap.")
                }
            case let (.cylinder(cylinder), arc?):
                try checkCoaxial(origin: cylinder.origin, axis: cylinder.axis, radius: cylinder.radius, arc: arc.circle, normal: normal, refuse)
            case let (.analytic(.cylinder(origin, axis, radius)), arc?):
                try checkCoaxial(origin: origin, axis: axis, radius: radius, arc: arc.circle, normal: normal, refuse)
            default:
                throw refuse("A blended loop's walls are planes through its lines and cylinders through its arcs.")
            }
            let side = try wallSide(walls[0], cap: normal, at: run.start, model: model)
            guard side != 0, rise == 0 || rise == side else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): a loop whose walls run down from the cap at
                // some edges and up at others turns between a convex and a concave band, which is
                // not built, so it is refused. Production path: CapLoopBlendBuilder from Fillet and
                // Chamfer. Complete only when such loops blend, verified by a plate's step.
                throw refuse("A blended loop's walls all run down from its cap or all rise from it.")
            }
            rise = side
            segments.append(Segment(edgeID: use.edgeID, wallFaceID: walls[0], start: run.start, end: run.end, arc: run.arc))
            samples.append(run.start)
            if let arc = run.arc {
                samples.append(try Curve3D.circle(arc.circle).point(at: (arc.from + arc.to) / 2, tolerance: tolerance))
            }
        }
        // The cap lies to the left of the loop about its normal when the loop winds that way about
        // the region it bounds: counterclockwise for the outer loop, clockwise for a hole's.
        var winding = Vector3D.zero
        for (a, b) in zip(samples, samples.dropFirst() + samples.prefix(1)) { winding = winding + (a - samples[0]).cross(b - samples[0]) }
        let counterclockwise = winding.dot(normal) > 0
        let inwardSense: Double = (loop.role == .outer) == counterclockwise ? 1 : -1
        return CapLoop(capFaceID: capFaceID, normal: normal, rise: rise, segments: segments, inwardSense: inwardSense)
    }

    private func checkCoaxial(origin: Point3D, axis: Vector3D, radius: Double, arc: Circle3D, normal: Vector3D,
                              _ refuse: (String) -> KernelError) throws {
        let offset = arc.center - origin
        guard axis.cross(normal).length <= tolerance.angle * max(axis.length, 1),
              abs(radius - arc.radius) <= tolerance.distance,
              (offset - axis * (offset.dot(axis) / axis.dot(axis))).length <= tolerance.distance else {
            throw refuse("A blended loop's arcs bound cylinders coaxial with them.")
        }
    }

    /// −1 when the wall's vertices all lie below the cap's plane through `point` (against its
    /// outward normal `cap`), +1 when all lie above it, some strictly; 0 when it crosses the plane.
    private func wallSide(_ wall: FaceID, cap: Vector3D, at point: Point3D, model: BRepModel) throws -> Double {
        guard let face = model.faces[wall] else { throw TopologyError.missingReference("Missing wall.") }
        let heights = try face.loops.flatMap { loopID -> [Double] in
            guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("Missing wall loop.") }
            return try loop.edges.flatMap { use -> [Double] in
                guard let edge = model.edges[use.edgeID], let start = model.vertices[edge.startVertexID]?.point,
                      let end = model.vertices[edge.endVertexID]?.point else {
                    throw TopologyError.missingReference("Missing wall edge.")
                }
                return [(start - point).dot(cap), (end - point).dot(cap)]
            }
        }
        if heights.allSatisfy({ $0 <= tolerance.distance }), heights.contains(where: { $0 < -tolerance.distance }) { return -1 }
        if heights.allSatisfy({ $0 >= -tolerance.distance }), heights.contains(where: { $0 > tolerance.distance }) { return 1 }
        return 0
    }

    // MARK: - Curves on the faces beside

    /// The pcurve of `circle` from `t0` to `t1` on a plane (its harmonic image) or on a coaxial
    /// cylinder (a line of constant height turning as the circle does).
    private func circlePcurve(_ circle: Circle3D, from t0: Double, to t1: Double, on surface: Surface3D) throws -> SurfaceParameterCurve {
        let curve = Curve3D.circle(circle)
        switch surface {
        case .plane, .analytic(.plane):
            let center = try surface.parameterProjection(of: circle.center, tolerance: tolerance)
            let cosine = try surface.parameterProjection(of: curve.point(at: 0, tolerance: tolerance), tolerance: tolerance)
            let sine = try surface.parameterProjection(of: curve.point(at: Double.pi / 2, tolerance: tolerance), tolerance: tolerance)
            return .harmonic(center: Point2D(x: center.u, y: center.v), cosine: Point2D(x: cosine.u - center.u, y: cosine.v - center.v),
                             sine: Point2D(x: sine.u - center.u, y: sine.v - center.v), startParameter: t0, endParameter: t1)
        default:
            let p = try surface.parameterProjection(of: curve.point(at: t0, tolerance: tolerance), tolerance: tolerance)
            let middle = try surface.parameterProjection(of: curve.point(at: t0 + (t1 - t0) / 4, tolerance: tolerance), tolerance: tolerance)
            let sense: Double = nearestTurn(from: p.u, to: middle.u) >= p.u ? 1 : -1
            return .constantV(v: p.v, uStart: p.u, uEnd: p.u + sense * abs(t1 - t0))
        }
    }

    /// A straight edge's pcurve on a plane or a cylinder (its rulings): a straight segment between
    /// its ends' parameters.
    private func linePcurve(from p: Point3D, to q: Point3D, on surface: Surface3D) throws -> SurfaceParameterCurve {
        let (a, b) = (try surface.parameterProjection(of: p, tolerance: tolerance), try surface.parameterProjection(of: q, tolerance: tolerance))
        return .polyline([SurfaceParameter(u: a.u, v: a.v), SurfaceParameter(u: b.u, v: b.v)])
    }

    private func shortParameters(_ circle: Circle3D, from start: Point3D, to end: Point3D) throws -> (Double, Double) {
        let curve = Curve3D.circle(circle)
        let t0 = try curve.parameterProjection(of: start, tolerance: tolerance).parameter
        return (t0, nearestTurn(from: t0, to: try curve.parameterProjection(of: end, tolerance: tolerance).parameter))
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
