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
/// takes the whole loop, as a tangent chain does. A loop with sharp corners blends the tangent chain
/// holding the selected edge, open at those corners, when its walls run down from the cap and each
/// end lies on a plane square to the chain there (a D's rim ending on its flat side): the band ends
/// on its section in that plane, which takes the section across its corner. With Tangent Edges off
/// (`followsTangents` false) a chain is only the selected edges joined tangentially; where it stops at
/// a tangent joint the band closes on its section there, a flat face between the section and the
/// corner, the cap stepping back from its contact to the corner and the next wall keeping its seam's
/// top above the wall contact.
package struct CapLoopBlendBuilder {
    private let tolerance: ModelingTolerance
    private let followsTangents: Bool

    package init(tolerance: ModelingTolerance, followsTangents: Bool = true) {
        self.tolerance = tolerance
        self.followsTangents = followsTangents
    }

    /// The band's cross-section: a round's quarter circle of the radius along the cap and the
    /// wall, or a chamfer's line from its contact `cap` along the cap to its contact `wall` along
    /// the wall.
    package enum Section: Sendable {
        case round(Double)
        case chamfer(cap: Double, wall: Double)
        /// A Conic, Chordal or G2 fillet's section across the cap's right-angled corner with its
        /// wall: a Bézier curve of `degree` with `weights`, its control points `setback`-scaled
        /// steps (`cap` along the cap, `wall` along the wall) from the corner, from the cap
        /// contact to the wall contact.
        case profile(setback: Double, degree: Int, weights: [Double], points: [Step])

        package struct Step: Sendable {
            package let cap: Double
            package let wall: Double

            package init(cap: Double, wall: Double) {
                self.cap = cap
                self.wall = wall
            }
        }

        /// How far the band reaches along the cap, and along the wall.
        var distances: (cap: Double, wall: Double) {
            switch self {
            case let .round(radius): (radius, radius)
            case let .chamfer(cap, wall): (cap, wall)
            case let .profile(setback, _, _, _): (setback, setback)
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

    /// Where an open chain ends: the loop vertex, the chain's segment ending there (its first or its
    /// last), and the end face — the plane square to the chain through the vertex.
    private struct ChainEnd {
        let vertex: Point3D
        let segment: Segment
        let faceID: FaceID
        let neighbourEdgeID: EdgeID
        /// Whether the chain stops at a tangent joint (the next edge unselected), closing there.
        let smooth: Bool
    }

    /// The tangent chain of a cap's loop holding an edge: the cap face and loop, the chain's first
    /// loop index and length, and whether it is the whole loop closed on itself.
    private struct CapChain {
        let capFaceID: FaceID
        let loopID: LoopID
        let first: Int
        let count: Int
        let closed: Bool
    }

    /// A cap chain: the cap, its outward normal, whether the walls rise (+1) or fall (−1) from it,
    /// the chain's segments in order, the sense (+1 or −1) that turns `normal × tangent` into the
    /// cap, and the chain's two ends when it is open.
    private struct CapLoop {
        let capFaceID: FaceID
        let normal: Vector3D
        let rise: Double
        let segments: [Segment]
        let inwardSense: Double
        let ends: [ChainEnd]
    }

    /// A chain this builder blends, or why it does not.
    private enum Admission {
        case admitted(CapLoop)
        case refused(String)
    }

    /// Whether every edge of `edgeIDs` lies on a tangent loop of lines and arcs, holding an arc, of
    /// a planar face, or on such an open chain of a loop of lines and arcs that this builder ends:
    /// the chains this builder takes, which straight blends do not.
    package func admits(_ edgeIDs: [EdgeID], model: BRepModel) throws -> Bool {
        guard edgeIDs.isEmpty == false else { return false }
        for edgeID in edgeIDs {
            guard let chain = try capChain(containing: edgeID, selected: Set(edgeIDs), model: model) else { return false }
            if chain.closed { continue }
            guard case .admitted = try capLoop(chain, model: model) else { return false }
        }
        return true
    }

    package func request(featureID: FeatureID, bodyID: BodyID, selected: [(edgeID: EdgeID, subshapeID: SubshapeID)],
                         section shape: Section, context: EvaluationContext) throws -> BRepSewingRequest {
        let (dc, dw) = shape.distances
        let model = context.brep
        func refuse(_ message: String) -> KernelError {
            KernelError(phase: .evaluation, code: .unsupportedCapability, featureID: featureID, tolerance: tolerance, message: message)
        }
        guard let body = model.bodies[bodyID], body.kind == .solid, body.shellIDs.count == 1,
              let shell = model.shells[body.shellIDs[0]] else {
            throw refuse("A cap loop is blended on one single-shell solid.")
        }
        // Every chain the selection touches.
        var loops: [CapLoop] = []
        var seen: Set<String> = []
        for selection in selected {
            guard let chain = try capChain(containing: selection.edgeID, selected: Set(selected.map(\.edgeID)), model: model) else {
                throw refuse("A blended loop is a tangent loop of lines and arcs on a planar cap.")
            }
            guard seen.insert("\(chain.loopID):\(chain.first)").inserted else { continue }
            switch try capLoop(chain, model: model) {
            case let .admitted(loop):
                guard shell.faceIDs.contains(loop.capFaceID) else {
                    throw refuse("A blended loop lies on the blended solid.")
                }
                loops.append(loop)
            case let .refused(message):
                throw refuse(message)
            }
        }
        let chainEdgeIDs = Set(loops.flatMap { $0.segments.map(\.edgeID) })
        for end in loops.flatMap(\.ends) where chainEdgeIDs.contains(end.neighbourEdgeID) {
            // FIXME(INCOMPLETE_IMPLEMENTATION): chains blended on both sides of a sharp corner of
            // their cap meet at a mitre between their bands, which is not built, so they are
            // refused. Production path: CapLoopBlendBuilder from Fillet and Chamfer. Complete only
            // when such corners close, verified by a D's whole rim rounded.
            throw refuse("Blended chains of a cap meet at its sharp corners.")
        }
        let selectedParent = Dictionary(selected.map { ($0.edgeID, $0.subshapeID) }, uniquingKeysWith: { first, _ in first })
        var patches: [BRepSewingFacePatch] = []
        // Where each loop vertex lands on its cap and on its walls, and the segments each face's
        // edges move to.
        var vertexMoves: [FaceID: [(from: Point3D, to: Point3D)]] = [:]
        var segmentMoves: [FaceID: [(from: Segment, to: Segment)]] = [:]
        // Each open chain's end vertex on its end face: split into the cap contact and the wall
        // contact, the section between them.
        var endSplits: [FaceID: [(vertex: Point3D, cap: Point3D, wall: Point3D, inward: Vector3D, section: BRepSewingEdge)]] = [:]
        // Each chain stopping at a tangent joint: the cap stepping from its contact back to the
        // corner, the next wall's seam split at the wall contact.
        var capSteps: [FaceID: [(vertex: Point3D, cap: Point3D)]] = [:]
        var seamSplits: [FaceID: [(vertex: Point3D, wall: Point3D)]] = [:]
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
                    // A convex arc's cap contact runs the distance nearer its centre: a round of the
                    // arc's own radius collapses it to the centre, where the band is the ball's
                    // sphere; a larger one does not fit.
                    let convexArc = mStart.dot(arc.circle.center - segment.start) > 0
                    if convexArc, arc.circle.radius < dc - tolerance.distance {
                        throw refuse("A cap loop's blend is no larger than its convex arcs.")
                    }
                    let collapses = convexArc && abs(arc.circle.radius - dc) <= tolerance.distance
                    if collapses, case .profile = shape {
                        // FIXME(INCOMPLETE_IMPLEMENTATION): a Conic, Chordal or G2 band as large as a
                        // convex arc of its cap closes on the arc's axis, which is not built, so it
                        // is refused. Production path: CapLoopBlendBuilder from Fillet's non-round
                        // shapes. Complete only when such bands close, verified by a rounded
                        // block's rim filleted Conic by its corner radius.
                        throw refuse("A cap loop's Conic, Chordal or G2 fillet is smaller than its convex arcs.")
                    }
                    if collapses, case .chamfer = shape {
                        // FIXME(INCOMPLETE_IMPLEMENTATION): a chamfer as large as a convex arc of its
                        // cap closes on a cone's apex, which is not built, so it is refused.
                        // Production path: CapLoopBlendBuilder from Chamfer. Complete only when such
                        // chamfers close, verified by a rounded block's rim chamfered by its corner radius.
                        throw refuse("A cap loop's chamfer is smaller than its convex arcs.")
                    }
                    let capRadius = (segment.start + mStart * dc - arc.circle.center).length
                    capSegment = collapses
                        ? Segment(edgeID: segment.edgeID, wallFaceID: segment.wallFaceID, start: arc.circle.center, end: arc.circle.center, arc: nil)
                        : Segment(edgeID: segment.edgeID, wallFaceID: segment.wallFaceID, start: segment.start + mStart * dc,
                                  end: segment.end + mEnd * dc,
                                  arc: (Circle3D(center: arc.circle.center, normal: arc.circle.normal, radius: capRadius), arc.from, arc.to))
                    wallSegment = Segment(edgeID: segment.edgeID, wallFaceID: segment.wallFaceID, start: segment.start + wall * dw,
                                          end: segment.end + wall * dw,
                                          arc: (Circle3D(center: arc.circle.center + wall * dw, normal: arc.circle.normal,
                                                         radius: arc.circle.radius), arc.from, arc.to))
                } else {
                    capSegment = Segment(edgeID: segment.edgeID, wallFaceID: segment.wallFaceID, start: segment.start + mStart * dc,
                                         end: segment.end + mEnd * dc, arc: nil)
                    wallSegment = Segment(edgeID: segment.edgeID, wallFaceID: segment.wallFaceID, start: segment.start + wall * dw,
                                          end: segment.end + wall * dw, arc: nil)
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
            for (endIndex, end) in loop.ends.enumerated() {
                let m = try inward(end.segment, at: end.vertex)
                let (capPoint, wallPoint) = (end.vertex + m * dc, end.vertex + wall * dw)
                let parents = selectedParent[end.segment.edgeID].map { [$0] } ?? context.subshapeIDs(for: .edge(end.segment.edgeID))
                let curve = try section(shape, at: end.vertex, inward: m, wallDirection: wall,
                                        tangent: try segmentTangent(end.segment, at: end.vertex), from: capPoint, to: wallPoint)
                let edge = BRepSewingEdge(stableID: "loop:\(loopIndex):end:\(endIndex)", curve: curve.curve,
                                          startParameter: curve.start, endParameter: curve.end, startPoint: capPoint, endPoint: wallPoint,
                                          surfaceParameterCurve: .polyline([]), parentSubshapeIDs: parents)
                guard end.smooth else {
                    endSplits[end.faceID, default: []].append((end.vertex, capPoint, wallPoint, m, edge))
                    continue
                }
                capSteps[loop.capFaceID, default: []].append((end.vertex, capPoint))
                seamSplits[end.faceID, default: []].append((end.vertex, wallPoint))
                // The closure: the section, the wall contact up to the corner, the corner across to
                // the cap contact, facing back along the chain into the corner the band cut away.
                let atEnd = end.vertex.isApproximatelyEqual(to: end.segment.end, tolerance: tolerance.distance)
                let outward = try segmentTangent(end.segment, at: end.vertex) * (atEnd ? -1 : 1)
                let plane = Surface3D.plane(Plane3D(origin: end.vertex, normal: outward))
                func line(_ p: Point3D, _ q: Point3D, _ name: String) throws -> BRepSewingEdge {
                    let delta = q - p
                    return BRepSewingEdge(stableID: "loop:\(loopIndex):closure:\(endIndex):\(name)",
                                          curve: .line(Line3D(origin: p, direction: try delta.normalized(tolerance: tolerance.distance))),
                                          startParameter: 0, endParameter: delta.length, startPoint: p, endPoint: q,
                                          surfaceParameterCurve: try linePcurve(from: p, to: q, on: plane), parentSubshapeIDs: parents)
                }
                var closure = [try planarSection(edge, on: plane), try line(wallPoint, end.vertex, "wall"), try line(end.vertex, capPoint, "cap")]
                if (wallPoint - capPoint).cross(end.vertex - capPoint).dot(outward) < 0 {
                    closure = try closure.reversed().map(reversed)
                }
                patches.append(BRepSewingFacePatch(stableID: "loop:\(loopIndex):closure:\(endIndex)", surface: plane, orientation: .forward,
                    loops: [BRepSewingLoop(stableID: "loop:\(loopIndex):closure:\(endIndex):outer", role: .outer, edges: closure)],
                    parentSubshapeIDs: [loop.capFaceID, end.segment.wallFaceID].flatMap { context.subshapeIDs(for: .face($0)) }))
            }
        }
        // Every face beside a loop with its loop edges moved and the straight edges reaching them
        // shortened; every other face as it was.
        for (faceIndex, faceID) in shell.faceIDs.enumerated() {
            let source = try SourceBRepFacePatchBuilder().build(faceID: faceID, stableID: "source-face:\(faceIndex)", from: model,
                                                                sourceSubshapes: context.subshapes.entries, tolerance: tolerance).patch
            let moves = vertexMoves[faceID] ?? []
            let splits = endSplits[faceID] ?? []
            let steps = capSteps[faceID] ?? []
            let seams = seamSplits[faceID] ?? []
            guard moves.isEmpty == false || splits.isEmpty == false || seams.isEmpty == false else {
                patches.append(source)
                continue
            }
            guard moves.isEmpty || splits.isEmpty else {
                throw refuse("A blended chain ends on a face it also blends.")
            }
            /// Where an end face's edge leaving a split vertex toward `other` starts now: the cap
            /// contact along the cap's line, the wall contact along the wall's.
            func split(_ vertex: Point3D, toward other: Point3D) throws -> Point3D? {
                guard let split = splits.first(where: { $0.vertex.isApproximatelyEqual(to: vertex, tolerance: tolerance.distance) }) else {
                    return nil
                }
                let direction = try (other - vertex).normalized(tolerance: tolerance.distance)
                let down = try (split.wall - split.vertex).normalized(tolerance: tolerance.distance)
                if direction.cross(split.inward).length <= tolerance.angle, direction.dot(split.inward) > 0 { return split.cap }
                if direction.cross(down).length <= tolerance.angle, direction.dot(down) > 0 { return split.wall }
                throw refuse("A blended chain's end face runs along the cap and the wall from its corner.")
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
            /// An edge with its ends moved: a loop segment becomes its moved segment, run the way the
            /// edge runs; a straight edge reaching a moved vertex is shortened.
            func movedEdge(_ edge: BRepSewingEdge, start: Point3D?, end: Point3D?) throws -> BRepSewingEdge {
                guard start != nil || end != nil else { return edge }
                let (p, q) = (start ?? edge.startPoint, end ?? edge.endPoint)
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
            }
            /// A seam of the next wall split where the wall contact crosses it, its trimming curve
            /// cut at the same fraction (straight on the wall's chart).
            func splitSeam(_ edge: BRepSewingEdge) throws -> [BRepSewingEdge]? {
                guard let seam = seams.first(where: { $0.vertex.isApproximatelyEqual(to: edge.startPoint, tolerance: tolerance.distance)
                    || $0.vertex.isApproximatelyEqual(to: edge.endPoint, tolerance: tolerance.distance) }),
                      case .line = edge.curve else { return nil }
                let length = (edge.endPoint - edge.startPoint).length
                // The seam runs from the corner down through the wall contact; the wall's other
                // edges at the corner (its rim) are left whole.
                guard (seam.wall - edge.startPoint).cross(edge.endPoint - edge.startPoint).length <= tolerance.distance * length else {
                    return nil
                }
                let fraction = (seam.wall - edge.startPoint).length / length
                guard fraction > 0, fraction < 1 else {
                    throw refuse("A blended chain's next wall has a straight seam below its corner.")
                }
                let (a, b) = (try edge.surfaceParameterCurve.parameter(atNormalizedFraction: 0, tolerance: tolerance),
                              try edge.surfaceParameterCurve.parameter(atNormalizedFraction: 1, tolerance: tolerance))
                let middle = SurfaceParameter(u: a.u + (b.u - a.u) * fraction, v: a.v + (b.v - a.v) * fraction)
                func piece(_ p: Point3D, _ q: Point3D, _ pp: SurfaceParameter, _ qp: SurfaceParameter, _ name: String) throws -> BRepSewingEdge {
                    let delta = q - p
                    return BRepSewingEdge(stableID: "\(edge.stableID):\(name)",
                                          curve: .line(Line3D(origin: p, direction: try delta.normalized(tolerance: tolerance.distance))),
                                          startParameter: 0, endParameter: delta.length, startPoint: p, endPoint: q,
                                          surfaceParameterCurve: .polyline([pp, qp]), parentSubshapeIDs: edge.parentSubshapeIDs)
                }
                return [try piece(edge.startPoint, seam.wall, a, middle, "0"), try piece(seam.wall, edge.endPoint, middle, b, "1")]
            }
            let loops = try source.loops.map { loop in
                let mapped = try loop.edges.flatMap { edge -> [BRepSewingEdge] in
                    if let pieces = try splitSeam(edge) { return pieces }
                    // A segment collapsing to its arc's centre leaves the cap.
                    if let move = segments.first(where: { matches(edge, $0.from) }),
                       move.to.start.isApproximatelyEqual(to: move.to.end, tolerance: tolerance.distance) {
                        return []
                    }
                    // An edge beyond a chain stopping at a tangent joint keeps the corner.
                    let isSegment = segments.contains { matches(edge, $0.from) }
                    func stays(_ point: Point3D) -> Bool {
                        !isSegment && steps.contains { $0.vertex.isApproximatelyEqual(to: point, tolerance: tolerance.distance) }
                    }
                    let start = try split(edge.startPoint, toward: edge.endPoint) ?? (stays(edge.startPoint) ? nil : moved(edge.startPoint))
                    let end = try split(edge.endPoint, toward: edge.startPoint) ?? (stays(edge.endPoint) ? nil : moved(edge.endPoint))
                    let shortened = try movedEdge(edge, start: start, end: end)
                    // The section at a split corner follows the edge running into it.
                    guard let corner = splits.first(where: { $0.vertex.isApproximatelyEqual(to: edge.endPoint, tolerance: tolerance.distance) }) else {
                        return [shortened]
                    }
                    let section = shortened.endPoint.isApproximatelyEqual(to: corner.cap, tolerance: tolerance.distance)
                        ? corner.section : try reversed(corner.section)
                    return [shortened, try planarSection(section, on: source.surface)]
                }
                // The cap steps from a chain's contact back to the corner it stops at.
                var edges: [BRepSewingEdge] = []
                for (index, edge) in mapped.enumerated() {
                    edges.append(edge)
                    let next = mapped[(index + 1) % mapped.count]
                    guard edge.endPoint.isApproximatelyEqual(to: next.startPoint, tolerance: tolerance.distance) == false else { continue }
                    guard steps.contains(where: { step in
                        (step.cap.isApproximatelyEqual(to: edge.endPoint, tolerance: tolerance.distance)
                            && step.vertex.isApproximatelyEqual(to: next.startPoint, tolerance: tolerance.distance))
                            || (step.vertex.isApproximatelyEqual(to: edge.endPoint, tolerance: tolerance.distance)
                                && step.cap.isApproximatelyEqual(to: next.startPoint, tolerance: tolerance.distance))
                    }) else {
                        throw KernelError(phase: .evaluation, code: .topologyFailure, featureID: featureID, tolerance: tolerance,
                                          message: "A cap's loop does not close around its blended chain.")
                    }
                    let delta = next.startPoint - edge.endPoint
                    edges.append(BRepSewingEdge(stableID: "\(edge.stableID):step",
                                                curve: .line(Line3D(origin: edge.endPoint, direction: try delta.normalized(tolerance: tolerance.distance))),
                                                startParameter: 0, endParameter: delta.length, startPoint: edge.endPoint, endPoint: next.startPoint,
                                                surfaceParameterCurve: try linePcurve(from: edge.endPoint, to: next.startPoint, on: source.surface),
                                                parentSubshapeIDs: edge.parentSubshapeIDs))
                }
                return BRepSewingLoop(stableID: loop.stableID, role: loop.role, edges: edges)
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
        let (dc, dw) = shape.distances
        let d = dc
        let wallDirection = n * rise
        /// The section at a loop point: from the cap contact to the wall contact.
        func sectionEdge(_ name: String, at point: Point3D, inward m: Vector3D, tangent: Vector3D, reversed: Bool) throws -> BRepSewingEdge {
            let (capPoint, wallPoint) = (point + m * dc, point + wallDirection * dw)
            let (p, q) = reversed ? (wallPoint, capPoint) : (capPoint, wallPoint)
            let curve = try section(shape, at: point, inward: m, wallDirection: wallDirection, tangent: tangent, from: p, to: q)
            return BRepSewingEdge(stableID: "\(stableID):\(name)", curve: curve.curve, startParameter: curve.start, endParameter: curve.end,
                                  startPoint: p, endPoint: q, surfaceParameterCurve: .polyline([]), parentSubshapeIDs: parents)
        }
        // A convex arc as round as the blend: the ball's sphere about the arc's centre, between the
        // sections at its ends (meeting at the centre on the cap) and the wall contact.
        if let arc = segment.arc, cap.start.isApproximatelyEqual(to: cap.end, tolerance: tolerance.distance) {
            let center = arc.circle.center + wallDirection * d
            let edges = [
                try sectionEdge("end", at: segment.end, inward: inward.end, tangent: try segmentTangent(segment, at: segment.end), reversed: false),
                try contactEdge("\(stableID):wall", wall, forward: false, parents: parents),
                try sectionEdge("start", at: segment.start, inward: inward.start, tangent: try segmentTangent(segment, at: segment.start), reversed: true),
            ]
            return try spherePatch(stableID: stableID, center: center, radius: d, edges: edges, parents: faceParents)
        }
        let surface: Surface3D
        if case let .profile(_, degree, weights, _) = shape {
            let startRow = profileCurve(shape, at: segment.start, inward: inward.start, wallDirection: wallDirection).controlPoints
            let knots = Array(repeating: 0.0, count: degree + 1) + Array(repeating: 1.0, count: degree + 1)
            if let arc = segment.arc {
                // The section turned about the arc's axis: rational quadratic in the turn, a piece
                // per quarter turn at most.
                let axis = try arc.circle.normal.normalized(tolerance: tolerance.distance)
                let sweep = arc.to - arc.from
                let pieces = max(1, Int((abs(sweep) / (0.5 * Double.pi) - 1e-9).rounded(.up)))
                let step = sweep / Double(pieces)
                func turned(_ point: Point3D, by angle: Double) -> Point3D {
                    let center = arc.circle.center + axis * (point - arc.circle.center).dot(axis)
                    let offset = point - center
                    return center + offset * cos(angle) + axis.cross(offset) * sin(angle)
                }
                var rows: [[Point3D]] = []
                var rowWeights: [[Double]] = []
                var vKnots: [Double] = [0, 0, 0]
                for piece in 0...pieces {
                    let angle = step * Double(piece)
                    rows.append(startRow.map { turned($0, by: angle) })
                    rowWeights.append(weights)
                    guard piece < pieces else { break }
                    rows.append(startRow.map { point in
                        let center = arc.circle.center + axis * (point - arc.circle.center).dot(axis)
                        return center + ((turned(point, by: angle) - center) + (turned(point, by: angle + step) - center)) * (1 / (1 + cos(step)))
                    })
                    rowWeights.append(weights.map { $0 * cos(0.5 * step) })
                    if piece > 0 { vKnots += [Double(piece) / Double(pieces), Double(piece) / Double(pieces)] }
                }
                vKnots += [1, 1, 1]
                let spline = BSplineSurface3D(uDegree: degree, vDegree: 2, uKnots: knots, vKnots: vKnots, controlPoints: rows, weights: rowWeights)
                try spline.validate(tolerance: tolerance)
                surface = .bSpline(spline)
            } else {
                // The section carried along the line.
                let endRow = profileCurve(shape, at: segment.end, inward: inward.end, wallDirection: wallDirection).controlPoints
                let spline = BSplineSurface3D(uDegree: degree, vDegree: 1, uKnots: knots, vKnots: [0, 0, 1, 1],
                                              controlPoints: [startRow, endRow], weights: [weights, weights])
                try spline.validate(tolerance: tolerance)
                surface = .bSpline(spline)
            }
        } else if let arc = segment.arc {
            let center = arc.circle.center
            let axisNormal = try arc.circle.normal.normalized(tolerance: tolerance.distance)
            let capRadius = (cap.start - center).length
            switch shape {
            case .round:
                surface = .analytic(.torus(center: center + wallDirection * d, axis: axisNormal, majorRadius: capRadius, minorRadius: d))
            case .chamfer:
                // The line from the cap's contact to the wall's, turning `dc` across in `dw` along the
                // wall, meets the axis at the apex.
                let outward = arc.circle.radius > capRadius ? 1.0 : -1.0
                let apexHeight = -rise * outward * capRadius * dw / dc
                let axisDirection = n * (rise * outward)
                surface = .analytic(.cone(apex: center + n * apexHeight, axis: axisDirection, halfAngle: atan2(dc, dw)))
            case .profile:
                throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: tolerance, message: "A profile band is built above.")
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
            case .profile:
                throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: tolerance, message: "A profile band is built above.")
            }
        }
        func tangent(at point: Point3D) throws -> Vector3D { try segmentTangent(segment, at: point) }
        // The loop: cap contact forward, the end's section to the wall, wall contact back, the start's
        // section up to the cap; pcurves from the band's own parameters.
        var edges = [
            try contactEdge("\(stableID):cap", cap, forward: true, parents: parents),
            try sectionEdge("end", at: segment.end, inward: inward.end, tangent: try tangent(at: segment.end), reversed: false),
            try contactEdge("\(stableID):wall", wall, forward: false, parents: parents),
            try sectionEdge("start", at: segment.start, inward: inward.start, tangent: try tangent(at: segment.start), reversed: true),
        ]
        if case .profile = shape {
            // The band's own lines: the section across in u, the chain along in v.
            let lines: [SurfaceParameterCurve] = [
                .constantU(u: 0, vStart: 0, vEnd: 1), .constantV(v: 1, uStart: 0, uEnd: 1),
                .constantU(u: 1, vStart: 1, vEnd: 0), .constantV(v: 0, uStart: 1, uEnd: 0),
            ]
            edges = zip(edges, lines).map { edge, line in
                BRepSewingEdge(stableID: edge.stableID, curve: edge.curve, startParameter: edge.startParameter, endParameter: edge.endParameter,
                               startPoint: edge.startPoint, endPoint: edge.endPoint, surfaceParameterCurve: line,
                               parentSubshapeIDs: edge.parentSubshapeIDs)
            }
        } else {
            edges = try chainedPcurves(edges, on: surface)
        }
        // Facing away from the material: toward the corner a convex band cuts off, away from the
        // corner a concave one fills; judged at the segment's middle, where the band runs at 45°.
        let corner: Point3D
        if let arc = segment.arc {
            corner = try Curve3D.circle(arc.circle).point(at: (arc.from + arc.to) / 2, tolerance: tolerance)
        } else {
            corner = segment.start + (segment.end - segment.start) * 0.5
        }
        let bandPoint: Point3D
        switch shape {
        case .round: bandPoint = corner + (try inwardAt(corner) + wallDirection) * (d * (1 - 0.5.squareRoot()))
        case .chamfer: bandPoint = corner + (try inwardAt(corner)) * (dc / 2) + wallDirection * (dw / 2)
        case .profile:
            bandPoint = try Curve3D.bSpline(profileCurve(shape, at: corner, inward: try inwardAt(corner), wallDirection: wallDirection))
                .point(at: 0.5, tolerance: tolerance)
        }
        let uv: (u: Double, v: Double)
        if case .profile = shape {
            uv = (0.5, 0.5)
        } else {
            let projected = try surface.parameterProjection(of: bandPoint, tolerance: tolerance)
            uv = (projected.u, projected.v)
        }
        let facing = try surface.normal(u: uv.u, v: uv.v, tolerance: tolerance).dot(corner - bandPoint) * -rise >= 0
        let loopEdges = try orientedLoop(edges, on: surface, facing: facing)
        return BRepSewingFacePatch(stableID: stableID, surface: surface, orientation: facing ? .forward : .reversed,
                                   loops: [BRepSewingLoop(stableID: "\(stableID):outer", role: .outer, edges: loopEdges)],
                                   parentSubshapeIDs: faceParents)
    }

    /// The band's section at a chain point from `p` to `q` (its cap and wall contacts, either way):
    /// a round's quarter circle about its centre `d` in from both, square to the chain, or a
    /// chamfer's line.
    private func section(_ shape: Section, at point: Point3D, inward m: Vector3D, wallDirection: Vector3D, tangent: Vector3D,
                         from p: Point3D, to q: Point3D) throws -> (curve: Curve3D, start: Double, end: Double) {
        switch shape {
        case let .round(d):
            let circle = Circle3D(center: point + (m + wallDirection) * d, normal: tangent, radius: d)
            let (t0, t1) = try shortParameters(circle, from: p, to: q)
            return (.circle(circle), t0, t1)
        case .chamfer:
            let delta = q - p
            return (.line(Line3D(origin: p, direction: try delta.normalized(tolerance: tolerance.distance))), 0, delta.length)
        case .profile:
            // Parameter 0 at the cap contact, 1 at the wall's.
            let curve = profileCurve(shape, at: point, inward: m, wallDirection: wallDirection)
            let fromCap = (p - curve.controlPoints[0]).length <= tolerance.distance
            return (.bSpline(curve), fromCap ? 0 : 1, fromCap ? 1 : 0)
        }
    }

    /// A profile section's Bézier curve at a chain point, from the cap contact to the wall contact.
    private func profileCurve(_ shape: Section, at point: Point3D, inward m: Vector3D, wallDirection: Vector3D) -> BSplineCurve3D {
        guard case let .profile(setback, degree, weights, steps) = shape else {
            return BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1], controlPoints: [point, point])
        }
        return BSplineCurve3D(
            degree: degree,
            knots: Array(repeating: 0.0, count: degree + 1) + Array(repeating: 1.0, count: degree + 1),
            controlPoints: steps.map { point + m * ($0.cap * setback) + wallDirection * ($0.wall * setback) },
            weights: weights
        )
    }

    /// A segment's unit tangent at a point, along the chain.
    private func segmentTangent(_ segment: Segment, at point: Point3D) throws -> Vector3D {
        if let arc = segment.arc {
            let radial = try (point - arc.circle.center).normalized(tolerance: tolerance.distance)
            return try (arc.circle.normal.cross(radial) * (arc.to >= arc.from ? 1 : -1)).normalized(tolerance: tolerance.distance)
        }
        return try (segment.end - segment.start).normalized(tolerance: tolerance.distance)
    }

    /// A section edge on the plane it ends a chain in, with its pcurve there.
    private func planarSection(_ edge: BRepSewingEdge, on surface: Surface3D) throws -> BRepSewingEdge {
        let pcurve: SurfaceParameterCurve
        if case let .circle(circle) = edge.curve {
            pcurve = try circlePcurve(circle, from: edge.startParameter, to: edge.endParameter, on: surface)
        } else if case .bSpline = edge.curve {
            pcurve = try ExactFacePcurveBuilder().surfaceParameterCurve(
                for: edge.curve, startParameter: edge.startParameter, endParameter: edge.endParameter, on: surface, tolerance: tolerance
            )
        } else {
            pcurve = try linePcurve(from: edge.startPoint, to: edge.endPoint, on: surface)
        }
        return BRepSewingEdge(stableID: edge.stableID, curve: edge.curve, startParameter: edge.startParameter,
                              endParameter: edge.endParameter, startPoint: edge.startPoint, endPoint: edge.endPoint,
                              surfaceParameterCurve: pcurve, parentSubshapeIDs: edge.parentSubshapeIDs)
    }

    /// A loop of great circles of the sphere about `center` as its patch, each edge's pcurve the
    /// great circle's, run counterclockwise seen from outside and facing out: the ball inside the
    /// material at a convex corner.
    private func spherePatch(stableID: String, center: Point3D, radius: Double, edges: [BRepSewingEdge],
                             parents: [SubshapeID]) throws -> BRepSewingFacePatch {
        var loop = try edges.map { edge -> BRepSewingEdge in
            let cosine = try (edge.curve.point(at: 0, tolerance: tolerance) - center).normalized(tolerance: tolerance.distance)
            let sine = try (edge.curve.point(at: Double.pi / 2, tolerance: tolerance) - center).normalized(tolerance: tolerance.distance)
            return BRepSewingEdge(stableID: edge.stableID, curve: edge.curve, startParameter: edge.startParameter, endParameter: edge.endParameter,
                                  startPoint: edge.startPoint, endPoint: edge.endPoint,
                                  surfaceParameterCurve: .sphericalGreatCircle(cosine: cosine, sine: sine, startParameter: edge.startParameter,
                                                                               endParameter: edge.endParameter),
                                  parentSubshapeIDs: edge.parentSubshapeIDs)
        }
        let corners = loop.map(\.startPoint)
        let centroid = Point3D.origin + corners.reduce(Vector3D.zero) { $0 + ($1 - .origin) } * (1 / Double(corners.count))
        if (corners[1] - corners[0]).cross(corners[2] - corners[0]).dot(centroid - center) < 0 {
            loop = try loop.reversed().map(reversed)
        }
        let surface = Surface3D.analytic(.sphere(center: center, radius: radius))
        let outward = try (centroid - center).normalized(tolerance: tolerance.distance)
        let uv = try surface.parameterProjection(of: center + outward * radius, tolerance: tolerance)
        let facing = try surface.normal(u: uv.u, v: uv.v, tolerance: tolerance).dot(outward) >= 0
        return BRepSewingFacePatch(stableID: stableID, surface: surface, orientation: facing ? .forward : .reversed,
                                   loops: [BRepSewingLoop(stableID: "\(stableID):outer", role: .outer, edges: loop)],
                                   parentSubshapeIDs: parents)
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

    /// The tangent chain holding `edgeID` on a planar face's loop of lines and arcs: the whole loop
    /// when it is tangent at every joint, otherwise the run of segments tangent at their joints
    /// between two sharp corners; nil when the loop is not of lines and arcs or the chain holds no arc.
    private func capChain(containing edgeID: EdgeID, selected: Set<EdgeID>, model: BRepModel) throws -> CapChain? {
        for (faceID, face) in model.faces.sorted(by: { $0.key < $1.key }) {
            guard case .plane? = model.geometry.surfaces[face.surfaceID] else { continue }
            for loopID in face.loops {
                guard let loop = model.loops[loopID], let index = loop.edges.firstIndex(where: { $0.edgeID == edgeID }) else { continue }
                let curves = loop.edges.compactMap { use in model.edges[use.edgeID].flatMap { model.geometry.curves[$0.curveID] } }
                guard curves.count == loop.edges.count,
                      curves.allSatisfy({ curve in
                          switch curve { case .line, .circle: return true; default: return false }
                      }) else { continue }
                let runs = try loop.edges.map { try run(of: $0, model: model) }
                let count = runs.count
                // Whether the chain runs on from each segment into the next: tangent there, and with
                // Tangent Edges off the next one selected too.
                let smooth = (0..<count).map { i in
                    let (before, after) = (runs[i], runs[(i + 1) % count])
                    return before.endTangent.cross(after.startTangent).length <= 1e-7 && before.endTangent.dot(after.startTangent) > 0
                }
                // The cap is the face whose loop runs on smoothly from the edge into an arc, whether or
                // not the chain follows it (with Tangent Edges off the walls beside a rounded
                // outline's line are planar too, and face order must not pick one of them).
                var reach = Set([index])
                var cursor = index
                while smooth[cursor], reach.insert((cursor + 1) % count).inserted { cursor = (cursor + 1) % count }
                cursor = index
                while smooth[(cursor - 1 + count) % count], reach.insert((cursor - 1 + count) % count).inserted { cursor = (cursor - 1 + count) % count }
                guard reach.contains(where: { runs[$0].arc != nil }) else { continue }
                let tangent = (0..<count).map { i in
                    smooth[i] && (followsTangents || (selected.contains(loop.edges[i].edgeID) && selected.contains(loop.edges[(i + 1) % count].edgeID)))
                }
                let chain: CapChain
                if tangent.allSatisfy({ $0 }) {
                    chain = CapChain(capFaceID: faceID, loopID: loopID, first: 0, count: count, closed: true)
                } else {
                    var first = index
                    while tangent[(first - 1 + count) % count] { first = (first - 1 + count) % count }
                    var last = index
                    while tangent[last] { last = (last + 1) % count }
                    chain = CapChain(capFaceID: faceID, loopID: loopID, first: first, count: (last - first + count) % count + 1, closed: false)
                }
                return chain
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

    /// The chain with its walls, checked: each segment's other face a wall square to the cap (a
    /// plane through a line, the coaxial cylinder through an arc), the walls all on one side; an
    /// open chain's walls running down from the cap and each end on a plane square to the chain.
    private func capLoop(_ chain: CapChain, model: BRepModel) throws -> Admission {
        guard let capFace = model.faces[chain.capFaceID], case let .plane(plane)? = model.geometry.surfaces[capFace.surfaceID],
              let loop = model.loops[chain.loopID] else {
            throw TopologyError.missingReference("Missing cap.")
        }
        guard let shell = model.shells.values.first(where: { $0.faceIDs.contains(chain.capFaceID) }) else {
            throw TopologyError.missingReference("Missing cap shell.")
        }
        let normal = try (capFace.orientation == .forward ? plane.normal : plane.normal * -1).normalized(tolerance: tolerance.distance)
        /// The one face other than the cap holding a loop edge, with its surface.
        func wall(of use: Coedge) throws -> (FaceID, Surface3D)? {
            let walls = try shell.faceIDs.filter { faceID in
                guard faceID != chain.capFaceID, let face = model.faces[faceID] else { return false }
                return try face.loops.contains { id in
                    guard let other = model.loops[id] else { throw TopologyError.missingReference("Missing loop.") }
                    return other.edges.contains { $0.edgeID == use.edgeID }
                }
            }
            guard walls.count == 1, let face = model.faces[walls[0]], let surface = model.geometry.surfaces[face.surfaceID] else { return nil }
            return (walls[0], surface)
        }
        let count = loop.edges.count
        var segments: [Segment] = []
        var rise = 0.0
        for offset in 0..<chain.count {
            let use = loop.edges[(chain.first + offset) % count]
            let run = try run(of: use, model: model)
            guard let (wallFaceID, wallSurface) = try wall(of: use) else {
                return .refused("A blended loop's edges each bound the cap and one wall.")
            }
            // The wall square to the cap: a plane holding the cap's normal, or the arc's coaxial cylinder.
            switch (wallSurface, run.arc) {
            case let (.plane(wallPlane), nil):
                guard abs(wallPlane.normal.dot(normal)) <= tolerance.angle * max(wallPlane.normal.length, 1) else {
                    return .refused("A blended loop's walls are square to its cap.")
                }
            case let (.cylinder(cylinder), arc?):
                guard coaxial(origin: cylinder.origin, axis: cylinder.axis, radius: cylinder.radius, arc: arc.circle, normal: normal) else {
                    return .refused("A blended loop's arcs bound cylinders coaxial with them.")
                }
            case let (.analytic(.cylinder(origin, axis, radius)), arc?):
                guard coaxial(origin: origin, axis: axis, radius: radius, arc: arc.circle, normal: normal) else {
                    return .refused("A blended loop's arcs bound cylinders coaxial with them.")
                }
            default:
                return .refused("A blended loop's walls are planes through its lines and cylinders through its arcs.")
            }
            let side = try wallSide(wallFaceID, cap: normal, at: run.start, model: model)
            guard side != 0, rise == 0 || rise == side else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): a loop whose walls run down from the cap at
                // some edges and up at others turns between a convex and a concave band, which is
                // not built, so it is refused. Production path: CapLoopBlendBuilder from Fillet and
                // Chamfer. Complete only when such loops blend, verified by a plate's step.
                return .refused("A blended loop's walls all run down from its cap or all rise from it.")
            }
            rise = side
            segments.append(Segment(edgeID: use.edgeID, wallFaceID: wallFaceID, start: run.start, end: run.end, arc: run.arc))
        }
        // The cap lies to the left of the loop about its normal when the loop winds that way about
        // the region it bounds: counterclockwise for the outer loop, clockwise for a hole's.
        var samples: [Point3D] = []
        for use in loop.edges {
            let run = try run(of: use, model: model)
            samples.append(run.start)
            if let arc = run.arc {
                samples.append(try Curve3D.circle(arc.circle).point(at: (arc.from + arc.to) / 2, tolerance: tolerance))
            }
        }
        var winding = Vector3D.zero
        for (a, b) in zip(samples, samples.dropFirst() + samples.prefix(1)) { winding = winding + (a - samples[0]).cross(b - samples[0]) }
        let counterclockwise = winding.dot(normal) > 0
        let inwardSense: Double = (loop.role == .outer) == counterclockwise ? 1 : -1
        guard chain.closed == false else {
            return .admitted(CapLoop(capFaceID: chain.capFaceID, normal: normal, rise: rise, segments: segments,
                                     inwardSense: inwardSense, ends: []))
        }
        guard chain.count < count else {
            return .refused("A blended chain ends at sharp corners of its cap's loop beside other edges.")
        }
        guard rise < 0 else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): an open chain whose walls rise from the cap (part
            // of a boss's base) fills its corner up to faces its ends meet, which is not built, so
            // it is refused. Production path: CapLoopBlendBuilder from Fillet and Chamfer. Complete
            // only when such chains blend, verified by a half disc's base on a plate.
            return .refused("An open blended chain's walls run down from its cap.")
        }
        // Each end on its neighbour's wall: a plane square to the chain there.
        var ends: [ChainEnd] = []
        for (neighbourIndex, segment, vertex) in [((chain.first - 1 + count) % count, segments[0], segments[0].start),
                                                  ((chain.first + chain.count) % count, segments[segments.count - 1],
                                                   segments[segments.count - 1].end)] {
            let neighbour = loop.edges[neighbourIndex]
            let tangent = try segmentTangent(segment, at: vertex)
            // A tangent joint the chain stops at closes on the section there.
            let next = try run(of: neighbour, model: model)
            let nextTangent = next.start.isApproximatelyEqual(to: vertex, tolerance: tolerance.distance) ? next.startTangent : next.endTangent
            if nextTangent.cross(tangent).length <= 1e-7 {
                guard let (faceID, _) = try wall(of: neighbour), faceID != segment.wallFaceID else {
                    return .refused("A blended chain stopping at a tangent joint meets another wall there.")
                }
                ends.append(ChainEnd(vertex: vertex, segment: segment, faceID: faceID, neighbourEdgeID: neighbour.edgeID, smooth: true))
                continue
            }
            guard let (faceID, surface) = try wall(of: neighbour), case let .plane(endPlane) = surface else {
                return .refused("An open blended chain ends on planes.")
            }
            let planeNormal = try endPlane.normal.normalized(tolerance: tolerance.distance)
            guard planeNormal.cross(tangent).length <= tolerance.angle else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): an open chain ending on a face oblique to it
                // needs its band trimmed by that face, which is not built, so it is refused.
                // Production path: CapLoopBlendBuilder from Fillet and Chamfer. Complete only when
                // such chains blend, verified by an arc's rim ending on a slanted side.
                return .refused("An open blended chain ends on planes square to it.")
            }
            // The neighbour runs from the corner into the cap, as the band's cap contact does.
            let other = try run(of: neighbour, model: model)
            let away = other.start.isApproximatelyEqual(to: vertex, tolerance: tolerance.distance) ? other.end - other.start : other.start - other.end
            guard away.dot(normal.cross(tangent) * inwardSense) > 0 else {
                return .refused("An open blended chain ends at convex corners of its cap.")
            }
            ends.append(ChainEnd(vertex: vertex, segment: segment, faceID: faceID, neighbourEdgeID: neighbour.edgeID, smooth: false))
        }
        return .admitted(CapLoop(capFaceID: chain.capFaceID, normal: normal, rise: rise, segments: segments,
                                 inwardSense: inwardSense, ends: ends))
    }

    private func coaxial(origin: Point3D, axis: Vector3D, radius: Double, arc: Circle3D, normal: Vector3D) -> Bool {
        let offset = arc.center - origin
        return axis.cross(normal).length <= tolerance.angle * max(axis.length, 1)
            && abs(radius - arc.radius) <= tolerance.distance
            && (offset - axis * (offset.dot(axis) / axis.dot(axis))).length <= tolerance.distance
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
