import Foundation
import CADCore
import CADGeometry
import CADTopology

/// A round or chamfer along a whole loop of a planar cap whose walls rise from the cap at some
/// edges and fall from it at others: a boss's foot running into a step's edges, where the step's
/// top loop is the arc of the boss's foot and the straight edges falling to the step's sides.
/// Each edge's band is its section swept along it — carried along a line, turned about an arc's
/// axis — filling the corner where its wall rises and cutting it away where its wall falls.
/// Bands meet on their shared section at a tangent joint, on the plane bisecting a sharp corner
/// between two straight edges whose walls run the same way (a mitre), and, at a sharp corner where
/// the walls turn, on a corner patch (`TurningCapLoopCornerPatchBuilder`) between their end
/// sections through the point where their cap contacts meet. The cap's loop moves onto the
/// contacts; each wall's edge moves its distance along the wall, and the edges running from the
/// loop's corners along the walls are cut there.
package struct TurningCapLoopBlendBuilder {
    package typealias Section = CapLoopBlendBuilder.Section

    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// One edge of the loop as the loop runs: its ends in that order, its circle when it is an arc
    /// (with the parameters it runs over), its wall, and whether the wall rises (+1) or falls (−1)
    /// from the cap.
    private struct Segment {
        let edgeID: EdgeID
        let wallFaceID: FaceID
        let start: Point3D
        let end: Point3D
        let arc: (circle: Circle3D, from: Double, to: Double)?
        let rise: Double
    }

    private struct Loop {
        let capFaceID: FaceID
        let normal: Vector3D
        /// The sense (+1 or −1) that turns `normal × tangent` into the cap.
        let inwardSense: Double
        let segments: [Segment]
    }

    /// How the bands meet at a loop vertex.
    private enum Corner {
        /// A tangent joint: one section ends the band before and starts the band after.
        case joint
        /// A sharp corner between straight edges whose walls run the same way: both bands end on
        /// the plane through the vertex with this normal, bisecting the corner.
        case mitre(normal: Vector3D)
        /// A sharp corner where the walls turn: both bands end on sections through `cap`, where
        /// their cap contacts meet, and a corner patch closes between them.
        case turn(cap: Point3D)
    }

    /// Whether `edgeIDs` are every edge of one loop of a planar face, each a line beside a plane
    /// square to the face or an arc beside its coaxial cylinder, the walls rising from the face at
    /// some edges and falling at others: the loops this builder blends, which no other does.
    package func admits(_ edgeIDs: [EdgeID], model: BRepModel) throws -> Bool {
        guard let loop = try loop(of: Set(edgeIDs), model: model) else { return false }
        return Set(loop.segments.map(\.rise)).count > 1
    }

    package func request(featureID: FeatureID, bodyID: BodyID, selected: [(edgeID: EdgeID, subshapeID: SubshapeID)],
                         section shape: Section, context: EvaluationContext) throws -> BRepSewingRequest {
        let model = context.brep
        func refuse(_ message: String) -> KernelError {
            KernelError(phase: .evaluation, code: .unsupportedCapability, featureID: featureID, tolerance: tolerance, message: message)
        }
        guard let body = model.bodies[bodyID], body.kind == .solid, body.shellIDs.count == 1,
              let shell = model.shells[body.shellIDs[0]] else {
            throw refuse("A turning cap loop is blended on one single-shell solid.")
        }
        guard let loop = try loop(of: Set(selected.map(\.edgeID)), model: model), shell.faceIDs.contains(loop.capFaceID) else {
            throw refuse("A turning cap loop is every edge of one loop of a planar face of the blended solid.")
        }
        let (dc, dw) = shape.distances
        let n = loop.normal
        let segments = loop.segments
        let count = segments.count
        let parentOf = Dictionary(selected.map { ($0.edgeID, $0.subshapeID) }, uniquingKeysWith: { first, _ in first })
        func parents(_ segment: Segment) -> [SubshapeID] {
            parentOf[segment.edgeID].map { [$0] } ?? context.subshapeIDs(for: .edge(segment.edgeID))
        }
        func tangent(_ segment: Segment, at point: Point3D) throws -> Vector3D {
            if let arc = segment.arc {
                let radial = try (point - arc.circle.center).normalized(tolerance: tolerance.distance)
                return try (arc.circle.normal.cross(radial) * (arc.to >= arc.from ? 1 : -1)).normalized(tolerance: tolerance.distance)
            }
            return try (segment.end - segment.start).normalized(tolerance: tolerance.distance)
        }
        func inward(_ segment: Segment, at point: Point3D) throws -> Vector3D {
            try n.cross(try tangent(segment, at: point)).normalized(tolerance: tolerance.distance) * loop.inwardSense
        }
        /// The section at a point of a segment, from its cap contact to its wall contact.
        func section(_ segment: Segment, at point: Point3D) throws -> BSplineCurve3D {
            let m = try inward(segment, at: point)
            let wall = n * segment.rise
            let curve: BSplineCurve3D
            switch shape {
            case let .round(d):
                curve = BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1], controlPoints: [point + m * d, point, point + wall * d],
                                       weights: [1, 0.5.squareRoot(), 1])
            case let .chamfer(cap, wallDistance):
                curve = BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1], controlPoints: [point + m * cap, point + wall * wallDistance])
            case let .profile(setback, degree, weights, steps):
                curve = BSplineCurve3D(degree: degree,
                                       knots: Array(repeating: 0.0, count: degree + 1) + Array(repeating: 1.0, count: degree + 1),
                                       controlPoints: steps.map { point + m * ($0.cap * setback) + wall * ($0.wall * setback) },
                                       weights: weights)
            }
            try curve.validate(tolerance: tolerance)
            return curve
        }

        // The corners: corner i lies where segment i ends and segment i + 1 starts.
        var corners: [Corner] = []
        for index in 0..<count {
            let (a, b) = (segments[index], segments[(index + 1) % count])
            let vertex = a.end
            let (ta, tb) = (try tangent(a, at: vertex), try tangent(b, at: vertex))
            if ta.cross(tb).length <= 1e-7, ta.dot(tb) > 0 {
                guard a.rise == b.rise else {
                    // FIXME(INCOMPLETE_IMPLEMENTATION): a loop whose walls turn from rising to
                    // falling at a tangent joint (a plate's step running smoothly into its edge)
                    // turns between a filling and a cutting band along one section, which is not
                    // built, so it is refused. Production path: TurningCapLoopBlendBuilder from
                    // Fillet. Complete only when such loops blend, verified by a stepped plate's
                    // top loop rounded where the step meets its edge tangentially.
                    throw refuse("A blended loop's walls turn from rising to falling at sharp corners.")
                }
                corners.append(.joint)
            } else if a.rise == b.rise {
                guard a.arc == nil, b.arc == nil else {
                    // FIXME(INCOMPLETE_IMPLEMENTATION): bands meeting at a sharp corner beside an
                    // arc whose walls run the same way meet on a surface other than a plane, which
                    // is not built, so they are refused. Production path:
                    // TurningCapLoopBlendBuilder from Fillet. Complete only when such corners
                    // close, verified by a D's rim with its boss's foot rounded together.
                    throw refuse("Bands meeting at a sharp corner whose walls run the same way are straight.")
                }
                corners.append(.mitre(normal: try (ta + tb).normalized(tolerance: tolerance.distance)))
            } else {
                guard (a.rise < 0 ? a : b).arc == nil else {
                    // FIXME(INCOMPLETE_IMPLEMENTATION): a turning corner whose falling wall is a
                    // cylinder closes on a patch whose side along that wall is an arc, which is
                    // not built, so it is refused. Production path: TurningCapLoopBlendBuilder from
                    // Fillet. Complete only when such corners close, verified by a boss's foot
                    // rounded with a rounded step's edge.
                    throw refuse("A blended loop's walls turn at a corner whose falling wall is a plane.")
                }
                corners.append(.turn(cap: try capMeeting(a, b, at: vertex, inward: inward, distance: dc, normal: n)))
            }
        }

        /// Where segment `index`'s band ends at its start (`atEnd` false) or end: the vertex at a
        /// joint or mitre, the foot of the cap point at a turn.
        func stationPoint(_ index: Int, atEnd: Bool) throws -> Point3D {
            let segment = segments[index]
            let corner = corners[atEnd ? index : (index - 1 + count) % count]
            let vertex = atEnd ? segment.end : segment.start
            guard case let .turn(cap) = corner else { return vertex }
            return try foot(of: cap, on: segment)
        }
        // The rows each band ends on: at corner i, the end of segment i and the start of segment
        // i + 1 (one curve at a joint or mitre).
        var rows: [(before: BSplineCurve3D, after: BSplineCurve3D)] = []
        for index in 0..<count {
            let (a, b) = (segments[index], segments[(index + 1) % count])
            switch corners[index] {
            case .joint:
                let curve = try section(a, at: a.end)
                rows.append((curve, curve))
            case let .mitre(normal):
                // The section carried along the edge onto the bisecting plane, which is the other
                // edge's carried there too (its mirror image across the plane).
                let vertex = a.end
                let axis = try tangent(a, at: vertex)
                let curve = try section(a, at: vertex)
                let carried = BSplineCurve3D(degree: curve.degree, knots: curve.knots, controlPoints: curve.controlPoints.map { point in
                    point + axis * (-(point - vertex).dot(normal) / axis.dot(normal))
                }, weights: curve.weights)
                let other = try section(b, at: vertex)
                let otherAxis = try tangent(b, at: vertex)
                guard zip(carried.controlPoints, other.controlPoints).allSatisfy({ point, start in
                    (start + otherAxis * (-(start - vertex).dot(normal) / otherAxis.dot(normal)))
                        .isApproximatelyEqual(to: point, tolerance: tolerance.distance)
                }) else {
                    throw refuse("Bands mitred at a corner mirror each other across it.")
                }
                rows.append((carried, carried))
            case .turn:
                rows.append((try section(a, at: try stationPoint(index, atEnd: true)),
                             try section(b, at: try stationPoint((index + 1) % count, atEnd: false))))
            }
        }

        // Each band between its start row (from the corner before) and its end row.
        struct Band {
            let surface: BSplineSurface3D
            let start: BSplineCurve3D
            let end: BSplineCurve3D
            /// The cap and wall contacts from the start row's to the end row's.
            let cap: (curve: Curve3D, from: Double, to: Double)
            let wall: (curve: Curve3D, from: Double, to: Double)
        }
        var bands: [Band] = []
        for (index, segment) in segments.enumerated() {
            let (start, end) = (rows[(index - 1 + count) % count].after, rows[index].before)
            let (c0, c1) = (start.controlPoints[0], end.controlPoints[0])
            let (w0, w1) = (start.controlPoints[start.controlPoints.count - 1], end.controlPoints[end.controlPoints.count - 1])
            if let arc = segment.arc {
                let axis = try arc.circle.normal.normalized(tolerance: tolerance.distance)
                let circle = Curve3D.circle(arc.circle)
                let direction: Double = arc.to >= arc.from ? 1 : -1
                let (p0, p1) = (try stationPoint(index, atEnd: false), try stationPoint(index, atEnd: true))
                let t0 = try circle.parameterProjection(of: p0, tolerance: tolerance).parameter
                var sweep = (try circle.parameterProjection(of: p1, tolerance: tolerance).parameter - t0)
                    .truncatingRemainder(dividingBy: 2 * Double.pi)
                if sweep * direction < 0 { sweep += 2 * Double.pi * direction }
                guard abs(sweep) > tolerance.angle, abs(sweep) <= abs(arc.to - arc.from) + tolerance.angle else {
                    throw refuse("A blend fits its arcs between their corners.")
                }
                let surface = try turnedBand(start, about: arc.circle.center, axis: axis, sweep: sweep)
                let capCircle = Circle3D(center: arc.circle.center, normal: arc.circle.normal, radius: (c0 - arc.circle.center).length)
                let wallCircle = Circle3D(center: arc.circle.center + n * (segment.rise * dw), normal: arc.circle.normal,
                                          radius: arc.circle.radius)
                let ct0 = try Curve3D.circle(capCircle).parameterProjection(of: c0, tolerance: tolerance).parameter
                let wt0 = try Curve3D.circle(wallCircle).parameterProjection(of: w0, tolerance: tolerance).parameter
                bands.append(Band(surface: surface, start: start, end: end,
                                  cap: (.circle(capCircle), ct0, ct0 + sweep), wall: (.circle(wallCircle), wt0, wt0 + sweep)))
            } else {
                let axis = try tangent(segment, at: segment.start)
                guard zip(start.controlPoints, end.controlPoints).allSatisfy({ ($1 - $0).dot(axis) > tolerance.distance }) else {
                    throw refuse("A blend fits its straight edges between their corners.")
                }
                let surface = BSplineSurface3D(uDegree: start.degree, vDegree: 1, uKnots: start.knots, vKnots: [0, 0, 1, 1],
                                               controlPoints: [start.controlPoints, end.controlPoints], weights: [start.weights, end.weights])
                try surface.validate(tolerance: tolerance)
                func line(_ p: Point3D, _ q: Point3D) throws -> (Curve3D, Double, Double) {
                    (.line(Line3D(origin: p, direction: try (q - p).normalized(tolerance: tolerance.distance))), 0, (q - p).length)
                }
                bands.append(Band(surface: surface, start: start, end: end, cap: try line(c0, c1), wall: try line(w0, w1)))
            }
        }

        // Where each loop vertex moves along the walls: the blend's wall distance along the edge
        // leaving it between the walls (down at a turn), or along the wall at a joint between
        // segments of one wall.
        var images: [(vertex: Point3D, image: Point3D)] = []
        var turns: [Int: (s: Point3D, top: Line3D, topLength: Double, descent: BSplineCurve3D)] = [:]
        for index in 0..<count {
            let (a, b) = (segments[index], segments[(index + 1) % count])
            let vertex = a.end
            let image: Point3D
            switch corners[index] {
            case .joint, .mitre: image = vertex + n * (a.rise * dw)
            case .turn: image = vertex + n * -dw
            }
            let loopEdges = Set(segments.map(\.edgeID))
            let leaving = try shell.faceIDs.flatMap { faceID -> [EdgeID] in
                guard let face = model.faces[faceID] else { throw TopologyError.missingReference("Missing face.") }
                return try face.loops.flatMap { loopID -> [EdgeID] in
                    guard let faceLoop = model.loops[loopID] else { throw TopologyError.missingReference("Missing loop.") }
                    return faceLoop.edges.map(\.edgeID)
                }
            }.filter { edgeID in
                guard loopEdges.contains(edgeID) == false, let edge = model.edges[edgeID],
                      let p = model.vertices[edge.startVertexID]?.point, let q = model.vertices[edge.endVertexID]?.point else { return false }
                return p.isApproximatelyEqual(to: vertex, tolerance: tolerance.distance) || q.isApproximatelyEqual(to: vertex, tolerance: tolerance.distance)
            }
            for edgeID in Set(leaving) {
                guard let edge = model.edges[edgeID], case .line? = model.geometry.curves[edge.curveID],
                      let p = model.vertices[edge.startVertexID]?.point, let q = model.vertices[edge.endVertexID]?.point else {
                    throw refuse("The edges leaving a blended loop's corners along its walls are straight.")
                }
                let other = p.isApproximatelyEqual(to: vertex, tolerance: tolerance.distance) ? q : p
                let along = other - vertex
                guard (image - vertex).cross(along).length <= tolerance.distance * along.length,
                      (image - vertex).dot(along) > 0, along.length > dw + tolerance.distance else {
                    throw refuse("A blend reaches no farther than the edges leaving its loop's corners along its walls.")
                }
            }
            images.append((vertex, image))
            guard case .turn = corners[index] else { continue }
            let (rising, risingIsBefore) = a.rise > 0 ? (a, true) : (b, false)
            let risingRow = risingIsBefore ? rows[index].before : rows[index].after
            let fallingRow = risingIsBefore ? rows[index].after : rows[index].before
            let q = risingRow.controlPoints[risingRow.controlPoints.count - 1]
            let t = fallingRow.controlPoints[fallingRow.controlPoints.count - 1]
            guard (t - image).length > tolerance.distance else {
                throw refuse("A turning corner's falling band ends apart from its corner.")
            }
            let foot = try stationPoint(risingIsBefore ? index : (index + 1) % count, atEnd: risingIsBefore)
            let descent = try TurningCapLoopCornerPatchBuilder(tolerance: tolerance)
                .descent(from: q, foot: foot, vertex: vertex, to: image, arc: rising.arc?.circle)
            turns[index] = (image, Line3D(origin: image, direction: try (t - image).normalized(tolerance: tolerance.distance)),
                            (t - image).length, descent)
        }

        var patches: [BRepSewingFacePatch] = []
        // The section and contact edges, shared by the patches beside them.
        func edge(_ stableID: String, _ curve: Curve3D, _ t0: Double, _ t1: Double, _ pcurve: SurfaceParameterCurve,
                  _ parents: [SubshapeID]) throws -> BRepSewingEdge {
            BRepSewingEdge(stableID: stableID, curve: curve, startParameter: t0, endParameter: t1,
                           startPoint: try curve.point(at: t0, tolerance: tolerance), endPoint: try curve.point(at: t1, tolerance: tolerance),
                           surfaceParameterCurve: pcurve, parentSubshapeIDs: parents)
        }
        let pcurves = ExactFacePcurveBuilder()
        // The bands, each counterclockwise in its parameters (u across the section from the cap,
        // v along the edge) about the normal facing out of the material.
        for (index, segment) in segments.enumerated() {
            let band = bands[index]
            let name = "turning-loop:band:\(index)"
            let edgeParents = parents(segment)
            var edges = [
                try edge("\(name):cap", band.cap.curve, band.cap.from, band.cap.to, .constantU(u: 0, vStart: 0, vEnd: 1), edgeParents),
                try edge("\(name):end", .bSpline(band.end), 0, 1, .constantV(v: 1, uStart: 0, uEnd: 1), edgeParents),
                try edge("\(name):wall", band.wall.curve, band.wall.to, band.wall.from, .constantU(u: 1, vStart: 1, vEnd: 0), edgeParents),
                try edge("\(name):start", .bSpline(band.start), 1, 0, .constantV(v: 0, uStart: 1, uEnd: 0), edgeParents),
            ]
            // Facing out: toward the corner a falling wall's band cuts away, away from the corner a
            // rising wall's band fills; judged at the band's middle against its edge there.
            let middle = try band.surface.point(u: 0.5, v: 0.5, tolerance: tolerance)
            let normal = try band.surface.normal(u: 0.5, v: 0.5, tolerance: tolerance)
            let corner = try nearest(middle, on: segment)
            let facing = normal.dot(corner - middle) * -segment.rise >= 0
            // The loop above runs clockwise in (u, v); facing the surface's normal, it runs back.
            if facing { edges = try edges.reversed().map(reversed) }
            patches.append(BRepSewingFacePatch(stableID: name, surface: .bSpline(band.surface), orientation: facing ? .forward : .reversed,
                                               loops: [BRepSewingLoop(stableID: "\(name):outer", role: .outer, edges: edges)],
                                               parentSubshapeIDs: [loop.capFaceID, segment.wallFaceID].flatMap { context.subshapeIDs(for: .face($0)) }))
        }
        // The corner patches.
        let cornerPatches = TurningCapLoopCornerPatchBuilder(tolerance: tolerance)
        for (index, turn) in turns.sorted(by: { $0.key < $1.key }) {
            let (a, b) = (segments[index], segments[(index + 1) % count])
            let risingIsBefore = a.rise > 0
            let (rising, falling) = risingIsBefore ? (a, b) : (b, a)
            let (risingBand, fallingBand) = risingIsBefore ? (bands[index], bands[(index + 1) % count])
                : (bands[(index + 1) % count], bands[index])
            let bottom = risingIsBefore ? rows[index].before : rows[index].after
            let left = risingIsBefore ? rows[index].after : rows[index].before
            let topCurve = BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
                                          controlPoints: [left.controlPoints[left.controlPoints.count - 1], turn.s])
            let wallNormal = try inward(falling, at: falling.start) * -1
            let surface = try cornerPatches.surface(bottom: bottom, left: left, top: topCurve, right: turn.descent,
                                                    risingBand: risingBand.surface, fallingBand: fallingBand.surface,
                                                    wallNormal: wallNormal, featureID: featureID)
            let name = "turning-loop:corner:\(index)"
            let edgeParents = parents(rising) + parents(falling)
            var edges = [
                try edge("\(name):rising", .bSpline(bottom), 0, 1, .constantV(v: 0, uStart: 0, uEnd: 1), edgeParents),
                try edge("\(name):descent", .bSpline(turn.descent), 0, 1, .constantU(u: 1, vStart: 0, vEnd: 1), edgeParents),
                try edge("\(name):wall", .line(turn.top), 0, turn.topLength, .constantV(v: 1, uStart: 1, uEnd: 0), edgeParents),
                try edge("\(name):falling", .bSpline(left), 1, 0, .constantU(u: 0, vStart: 1, vEnd: 0), edgeParents),
            ]
            // Facing out of the material at P, where the patch is tangent to the cap.
            let facing = try surface.normal(u: 0.05, v: 0.05, tolerance: tolerance).dot(n) >= 0
            if facing == false { edges = try edges.reversed().map(reversed) }
            patches.append(BRepSewingFacePatch(stableID: name, surface: .bSpline(surface), orientation: facing ? .forward : .reversed,
                                               loops: [BRepSewingLoop(stableID: "\(name):outer", role: .outer, edges: edges)],
                                               parentSubshapeIDs: [loop.capFaceID, rising.wallFaceID, falling.wallFaceID]
                                                .flatMap { context.subshapeIDs(for: .face($0)) }))
        }

        /// Segment `index`'s replacement on its wall, run along the segment: the descent from a
        /// turn's `S` up to its wall contact on a rising wall, or the falling wall's contact on
        /// from `S`, then the contact itself, then the same at its end.
        func wallPieces(_ index: Int, face name: String) throws -> [BRepSewingEdge] {
            let segment = segments[index]
            let band = bands[index]
            let edgeParents = parents(segment)
            var pieces: [BRepSewingEdge] = []
            let previous = (index - 1 + count) % count
            if let turn = turns[previous] {
                pieces.append(segment.rise > 0
                    ? try edge("\(name):turning:\(previous):descent", .bSpline(turn.descent), 1, 0, .polyline([]), edgeParents)
                    : try edge("\(name):turning:\(previous):wall", .line(turn.top), 0, turn.topLength, .polyline([]), edgeParents))
            }
            pieces.append(try edge("\(name):band:\(index):wall", band.wall.curve, band.wall.from, band.wall.to, .polyline([]), edgeParents))
            if let turn = turns[index] {
                pieces.append(segment.rise > 0
                    ? try edge("\(name):turning:\(index):descent", .bSpline(turn.descent), 0, 1, .polyline([]), edgeParents)
                    : try edge("\(name):turning:\(index):wall", .line(turn.top), turn.topLength, 0, .polyline([]), edgeParents))
            }
            return pieces
        }
        /// `edge` with its trimming curve on `surface`.
        func onFace(_ edge: BRepSewingEdge, _ surface: Surface3D) throws -> BRepSewingEdge {
            let pcurve: SurfaceParameterCurve
            if case let .bSpline(curve) = edge.curve, turns.values.contains(where: { $0.descent == curve }) {
                var descent = try cornerPatches.pcurve(of: curve, on: surface)
                if edge.startParameter > edge.endParameter { descent = try descent.reversed(tolerance: tolerance) }
                pcurve = descent
            } else {
                pcurve = try pcurves.surfaceParameterCurve(for: edge.curve, startParameter: edge.startParameter,
                                                          endParameter: edge.endParameter, on: surface, tolerance: tolerance)
            }
            return BRepSewingEdge(stableID: edge.stableID, curve: edge.curve, startParameter: edge.startParameter,
                                  endParameter: edge.endParameter, startPoint: edge.startPoint, endPoint: edge.endPoint,
                                  surfaceParameterCurve: pcurve, parentSubshapeIDs: edge.parentSubshapeIDs,
                                  startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                                  endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs)
        }
        func matches(_ edge: BRepSewingEdge, _ segment: Segment) -> Bool {
            (edge.startPoint.isApproximatelyEqual(to: segment.start, tolerance: tolerance.distance)
                && edge.endPoint.isApproximatelyEqual(to: segment.end, tolerance: tolerance.distance))
                || (edge.startPoint.isApproximatelyEqual(to: segment.end, tolerance: tolerance.distance)
                    && edge.endPoint.isApproximatelyEqual(to: segment.start, tolerance: tolerance.distance))
        }
        func image(of point: Point3D) -> Point3D? {
            images.first { $0.vertex.isApproximatelyEqual(to: point, tolerance: tolerance.distance) }?.image
        }
        // The cap on its contacts, the walls on theirs, the edges leaving the loop's corners cut,
        // every other face as it was.
        for (faceIndex, faceID) in shell.faceIDs.enumerated() {
            let source = try SourceBRepFacePatchBuilder().build(faceID: faceID, stableID: "source-face:\(faceIndex)", from: model,
                                                                sourceSubshapes: context.subshapes.entries, tolerance: tolerance).patch
            var changed = false
            let loops = try source.loops.map { sourceLoop -> BRepSewingLoop in
                var edges: [(edge: BRepSewingEdge, new: Bool)] = []
                for sourceEdge in sourceLoop.edges {
                    if let index = segments.firstIndex(where: { matches(sourceEdge, $0) }),
                       faceID == loop.capFaceID || faceID == segments[index].wallFaceID {
                        let segment = segments[index]
                        let forward = sourceEdge.startPoint.isApproximatelyEqual(to: segment.start, tolerance: tolerance.distance)
                        var pieces: [BRepSewingEdge]
                        if faceID == loop.capFaceID {
                            let band = bands[index]
                            pieces = [try edge("\(source.stableID):band:\(index):cap", band.cap.curve, band.cap.from, band.cap.to,
                                               .polyline([]), parents(segment))]
                        } else {
                            pieces = try wallPieces(index, face: source.stableID)
                        }
                        if forward == false { pieces = try pieces.reversed().map(reversed) }
                        edges += try pieces.map { (try onFace($0, source.surface), true) }
                        changed = true
                        continue
                    }
                    let (start, end) = (image(of: sourceEdge.startPoint), image(of: sourceEdge.endPoint))
                    guard start != nil || end != nil, faceID != loop.capFaceID else {
                        edges.append((sourceEdge, false))
                        continue
                    }
                    let (p, q) = (start ?? sourceEdge.startPoint, end ?? sourceEdge.endPoint)
                    let delta = q - p
                    guard case .line = sourceEdge.curve, delta.dot(sourceEdge.endPoint - sourceEdge.startPoint) > tolerance.distance * delta.length else {
                        throw refuse("A blend reaches no farther than the edges leaving its loop's corners along its walls.")
                    }
                    let line = Curve3D.line(Line3D(origin: p, direction: try delta.normalized(tolerance: tolerance.distance)))
                    let cut = BRepSewingEdge(stableID: sourceEdge.stableID, curve: line, startParameter: 0, endParameter: delta.length,
                                             startPoint: p, endPoint: q, surfaceParameterCurve: .polyline([]),
                                             parentSubshapeIDs: sourceEdge.parentSubshapeIDs,
                                             startVertexParentSubshapeIDs: sourceEdge.startVertexParentSubshapeIDs,
                                             endVertexParentSubshapeIDs: sourceEdge.endVertexParentSubshapeIDs)
                    edges.append((try onFace(cut, source.surface), true))
                    changed = true
                }
                return BRepSewingLoop(stableID: sourceLoop.stableID, role: sourceLoop.role,
                                      edges: try aligned(edges, on: source.surface))
            }
            patches.append(changed
                ? BRepSewingFacePatch(stableID: source.stableID, surface: source.surface, orientation: source.orientation,
                                      loops: loops, parentSubshapeIDs: source.parentSubshapeIDs)
                : source)
        }
        return BRepSewingRequest(featureID: featureID, bodyKind: .solid,
                                 shells: [BRepSewingShell(stableID: "shell:0", patches: patches)],
                                 bodyParentSubshapeIDs: context.subshapeIDs(for: .body(bodyID)))
    }

    // MARK: - Geometry

    /// The point where the cap contacts of `a` (ending at `vertex`) and `b` (starting there) meet
    /// nearest the vertex: lines and circles the distance into the cap from their edges.
    private func capMeeting(_ a: Segment, _ b: Segment, at vertex: Point3D,
                            inward: (Segment, Point3D) throws -> Vector3D, distance: Double, normal: Vector3D) throws -> Point3D {
        /// A contact as a line (a point and unit direction) or a circle (centre and radius), in the cap.
        enum Contact {
            case line(Point3D, Vector3D)
            case circle(Point3D, Double)
        }
        func contact(_ segment: Segment) throws -> Contact {
            let offset = try inward(segment, vertex) * distance
            if let arc = segment.arc {
                return .circle(arc.circle.center, (vertex + offset - arc.circle.center).length)
            }
            return .line(vertex + offset, try (segment.end - segment.start).normalized(tolerance: tolerance.distance))
        }
        var candidates: [Point3D] = []
        switch (try contact(a), try contact(b)) {
        case let (.line(p, d), .line(q, e)):
            // p + d s = q + e t, solved in the plane of d and e.
            let cross = d.cross(e)
            guard cross.length > tolerance.angle else { throw failure(.invalidInput, "A turning corner's contacts are parallel.") }
            let s = (q - p).cross(e).dot(cross) / cross.dot(cross)
            candidates = [p + d * s]
        case let (.line(p, d), .circle(c, r)), let (.circle(c, r), .line(p, d)):
            let offset = p - c
            let half = offset.dot(d)
            let discriminant = half * half - (offset.dot(offset) - r * r)
            guard discriminant >= 0 else { throw failure(.unsupportedCapability, "A blend is too large for its loop's turning corners.") }
            let root = discriminant.squareRoot()
            candidates = [p + d * (-half - root), p + d * (-half + root)]
        case let (.circle(c, r), .circle(k, s)):
            let between = k - c
            let separation = between.length
            guard separation > tolerance.distance else { throw failure(.invalidInput, "A turning corner's contacts are concentric.") }
            let along = (r * r - s * s + separation * separation) / (2 * separation)
            let height = r * r - along * along
            guard height >= 0 else { throw failure(.unsupportedCapability, "A blend is too large for its loop's turning corners.") }
            let axis = between * (1 / separation)
            let across = try normal.cross(axis).normalized(tolerance: tolerance.distance)
            candidates = [c + axis * along + across * height.squareRoot(), c + axis * along + across * -height.squareRoot()]
        }
        guard let nearest = candidates.min(by: { ($0 - vertex).length < ($1 - vertex).length }) else {
            throw failure(.unsupportedCapability, "A blend is too large for its loop's turning corners.")
        }
        return nearest
    }

    /// The foot of a cap point on a segment's edge, strictly within it.
    private func foot(of point: Point3D, on segment: Segment) throws -> Point3D {
        if let arc = segment.arc {
            let radial = try (point - arc.circle.center).normalized(tolerance: tolerance.distance)
            let foot = arc.circle.center + radial * arc.circle.radius
            let curve = Curve3D.circle(arc.circle)
            let t = try curve.parameterProjection(of: foot, tolerance: tolerance).parameter
            let (low, high) = (min(arc.from, arc.to), max(arc.from, arc.to))
            let turns = ((low - t) / (2 * Double.pi)).rounded(.up)
            let shifted = t + turns * 2 * Double.pi
            guard shifted > low + tolerance.angle, shifted < high - tolerance.angle else {
                throw failure(.unsupportedCapability, "A blend is too large for the arcs at its loop's turning corners.")
            }
            return foot
        }
        let delta = segment.end - segment.start
        let along = (point - segment.start).dot(delta) / delta.dot(delta)
        guard along > tolerance.relative, along < 1 - tolerance.relative else {
            throw failure(.unsupportedCapability, "A blend is too large for the edges at its loop's turning corners.")
        }
        return segment.start + delta * along
    }

    /// The point of a segment's edge nearest `point`, its circle carried on past its ends.
    private func nearest(_ point: Point3D, on segment: Segment) throws -> Point3D {
        if let arc = segment.arc {
            let offset = point - arc.circle.center
            let normal = try arc.circle.normal.normalized(tolerance: tolerance.distance)
            let inPlane = try (offset - normal * offset.dot(normal)).normalized(tolerance: tolerance.distance)
            return arc.circle.center + inPlane * arc.circle.radius
        }
        let delta = segment.end - segment.start
        return segment.start + delta * ((point - segment.start).dot(delta) / delta.dot(delta))
    }

    /// The band of an arc: `row` turned by `sweep` about the axis through `center`, rational
    /// quadratic in the turn with a piece per quarter turn at most; u across the row, v along the turn.
    private func turnedBand(_ row: BSplineCurve3D, about center: Point3D, axis: Vector3D, sweep: Double) throws -> BSplineSurface3D {
        let pieces = max(1, Int((abs(sweep) / (0.5 * Double.pi) - 1e-9).rounded(.up)))
        let step = sweep / Double(pieces)
        func turned(_ point: Point3D, by angle: Double) -> Point3D {
            let foot = center + axis * (point - center).dot(axis)
            let offset = point - foot
            return foot + offset * cos(angle) + axis.cross(offset) * sin(angle)
        }
        var rows: [[Point3D]] = []
        var weights: [[Double]] = []
        var vKnots: [Double] = [0, 0, 0]
        for piece in 0...pieces {
            let angle = step * Double(piece)
            rows.append(row.controlPoints.map { turned($0, by: angle) })
            weights.append(row.weights)
            guard piece < pieces else { break }
            rows.append(row.controlPoints.map { point in
                let foot = center + axis * (point - center).dot(axis)
                return foot + ((turned(point, by: angle) - foot) + (turned(point, by: angle + step) - foot)) * (1 / (1 + cos(step)))
            })
            weights.append(row.weights.map { $0 * cos(0.5 * step) })
            if piece > 0 { vKnots += [Double(piece) / Double(pieces), Double(piece) / Double(pieces)] }
        }
        vKnots += [1, 1, 1]
        let surface = BSplineSurface3D(uDegree: row.degree, vDegree: 2, uKnots: row.knots, vKnots: vKnots,
                                       controlPoints: rows, weights: weights)
        try surface.validate(tolerance: tolerance)
        return surface
    }

    // MARK: - Edges

    private func reversed(_ edge: BRepSewingEdge) throws -> BRepSewingEdge {
        BRepSewingEdge(stableID: edge.stableID, curve: edge.curve, startParameter: edge.endParameter, endParameter: edge.startParameter,
                       startPoint: edge.endPoint, endPoint: edge.startPoint,
                       surfaceParameterCurve: try edge.surfaceParameterCurve.reversed(tolerance: tolerance),
                       parentSubshapeIDs: edge.parentSubshapeIDs,
                       startVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs,
                       endVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs)
    }

    /// A loop's edges with each new edge's trimming curve shifted by whole periods of a periodic
    /// chart to start where the edge before it ends, from the first edge kept as it was.
    private func aligned(_ edges: [(edge: BRepSewingEdge, new: Bool)], on surface: Surface3D) throws -> [BRepSewingEdge] {
        guard case let .periodic(period) = surface.uDomain, edges.contains(where: \.new) else { return edges.map(\.edge) }
        var result = edges.map(\.edge)
        let first = edges.firstIndex { $0.new == false } ?? 0
        for step in 1..<max(edges.count, 1) + (edges[first].new ? 1 : 0) {
            let index = (first + step) % edges.count
            guard edges[index].new else { continue }
            let previous = result[(index - 1 + edges.count) % edges.count]
            let end = try previous.surfaceParameterCurve.parameter(atNormalizedFraction: 1, tolerance: tolerance)
            let start = try result[index].surfaceParameterCurve.parameter(atNormalizedFraction: 0, tolerance: tolerance)
            let turns = ((end.u - start.u) / period).rounded()
            guard turns != 0 else { continue }
            let edge = result[index]
            result[index] = BRepSewingEdge(stableID: edge.stableID, curve: edge.curve, startParameter: edge.startParameter,
                                           endParameter: edge.endParameter, startPoint: edge.startPoint, endPoint: edge.endPoint,
                                           surfaceParameterCurve: try shifted(edge.surfaceParameterCurve, by: turns * period),
                                           parentSubshapeIDs: edge.parentSubshapeIDs,
                                           startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                                           endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs)
        }
        return result
    }

    private func shifted(_ pcurve: SurfaceParameterCurve, by du: Double) throws -> SurfaceParameterCurve {
        switch pcurve {
        case let .constantU(u, v0, v1): return .constantU(u: u + du, vStart: v0, vEnd: v1)
        case let .constantV(v, u0, u1): return .constantV(v: v, uStart: u0 + du, uEnd: u1 + du)
        case let .polyline(points): return .polyline(points.map { SurfaceParameter(u: $0.u + du, v: $0.v) })
        case let .bSpline(curve):
            return .bSpline(BSplineCurve2D(degree: curve.degree, knots: curve.knots,
                                           controlPoints: curve.controlPoints.map { Point2D(x: $0.x + du, y: $0.y) }, weights: curve.weights))
        default:
            throw failure(.unsupportedCapability, "A blended wall's new edge has a trimming curve that cannot be carried around its chart.")
        }
    }

    // MARK: - Finding the loop

    /// The loop of a planar face whose edges are exactly `edgeIDs`, with its walls; nil when no
    /// such loop has lines beside planes square to the face and arcs beside coaxial cylinders.
    private func loop(of edgeIDs: Set<EdgeID>, model: BRepModel) throws -> Loop? {
        for (faceID, face) in model.faces.sorted(by: { $0.key < $1.key }) {
            guard case let .plane(plane)? = model.geometry.surfaces[face.surfaceID] else { continue }
            for loopID in face.loops {
                guard let faceLoop = model.loops[loopID], Set(faceLoop.edges.map(\.edgeID)) == edgeIDs,
                      faceLoop.edges.count == edgeIDs.count else { continue }
                guard let shell = model.shells.values.first(where: { $0.faceIDs.contains(faceID) }) else { return nil }
                let normal = try (face.orientation == .forward ? plane.normal : plane.normal * -1).normalized(tolerance: tolerance.distance)
                var segments: [Segment] = []
                var samples: [Point3D] = []
                for use in faceLoop.edges {
                    guard let edge = model.edges[use.edgeID], let curve = model.geometry.curves[edge.curveID],
                          let a = model.vertices[edge.startVertexID]?.point, let b = model.vertices[edge.endVertexID]?.point else {
                        throw TopologyError.missingReference("Missing loop edge.")
                    }
                    let forward = use.orientation == .forward
                    let (start, end) = forward ? (a, b) : (b, a)
                    var arc: (circle: Circle3D, from: Double, to: Double)?
                    switch curve {
                    case .line: break
                    case let .circle(circle):
                        guard a.isApproximatelyEqual(to: b, tolerance: tolerance.distance) == false else { return nil }
                        let t0 = try curve.parameterProjection(of: a, tolerance: tolerance).parameter
                        var t1 = try curve.parameterProjection(of: b, tolerance: tolerance).parameter
                        if let trim = edge.trim {
                            t1 = t0 + (trim.endParameter - trim.startParameter)
                        } else {
                            var delta = (t1 - t0).truncatingRemainder(dividingBy: 2 * Double.pi)
                            if delta > Double.pi { delta -= 2 * Double.pi }
                            if delta < -Double.pi { delta += 2 * Double.pi }
                            t1 = t0 + delta
                        }
                        arc = forward ? (circle, t0, t1) : (circle, t1, t0)
                    default:
                        return nil
                    }
                    // The one other face holding the edge: its wall, square to the cap.
                    let walls = try shell.faceIDs.filter { other in
                        guard other != faceID, let otherFace = model.faces[other] else { return false }
                        return try otherFace.loops.contains { id in
                            guard let otherLoop = model.loops[id] else { throw TopologyError.missingReference("Missing loop.") }
                            return otherLoop.edges.contains { $0.edgeID == use.edgeID }
                        }
                    }
                    guard walls.count == 1, let wallFace = model.faces[walls[0]],
                          let wallSurface = model.geometry.surfaces[wallFace.surfaceID] else { return nil }
                    switch (wallSurface, arc) {
                    case let (.plane(wallPlane), nil):
                        guard abs(wallPlane.normal.dot(normal)) <= tolerance.angle * max(wallPlane.normal.length, 1) else { return nil }
                    case let (.cylinder(cylinder), arc?):
                        guard coaxial(cylinder.origin, cylinder.axis, cylinder.radius, arc.circle, normal) else { return nil }
                    case let (.analytic(.cylinder(origin, axis, radius)), arc?):
                        guard coaxial(origin, axis, radius, arc.circle, normal) else { return nil }
                    default:
                        return nil
                    }
                    let rise = try wallSide(walls[0], edgeID: use.edgeID, capTangent: try runTangent(start: start, end: end, arc: arc),
                                            middle: try runMiddle(start: start, end: end, arc: arc), cap: normal, model: model)
                    guard rise != 0 else { return nil }
                    segments.append(Segment(edgeID: use.edgeID, wallFaceID: walls[0], start: start, end: end, arc: arc, rise: rise))
                    samples.append(start)
                    if let arc {
                        samples.append(try Curve3D.circle(arc.circle).point(at: (arc.from + arc.to) / 2, tolerance: tolerance))
                    }
                }
                // The cap lies to the left of its loop about its normal when the loop winds that
                // way about the region it bounds.
                var winding = Vector3D.zero
                for (p, q) in zip(samples, samples.dropFirst() + samples.prefix(1)) { winding = winding + (p - samples[0]).cross(q - samples[0]) }
                let inwardSense: Double = (faceLoop.role == .outer) == (winding.dot(normal) > 0) ? 1 : -1
                return Loop(capFaceID: faceID, normal: normal, inwardSense: inwardSense, segments: segments)
            }
        }
        return nil
    }

    private func coaxial(_ origin: Point3D, _ axis: Vector3D, _ radius: Double, _ arc: Circle3D, _ normal: Vector3D) -> Bool {
        let offset = arc.center - origin
        return axis.cross(normal).length <= tolerance.angle * max(axis.length, 1)
            && abs(radius - arc.radius) <= tolerance.distance
            && (offset - axis * (offset.dot(axis) / axis.dot(axis))).length <= tolerance.distance
    }

    /// The middle of a loop edge as the loop runs it.
    private func runMiddle(start: Point3D, end: Point3D, arc: (circle: Circle3D, from: Double, to: Double)?) throws -> Point3D {
        guard let arc else { return start + (end - start) * 0.5 }
        return try Curve3D.circle(arc.circle).point(at: (arc.from + arc.to) / 2, tolerance: tolerance)
    }

    /// The unit tangent at the middle of a loop edge as the loop runs it.
    private func runTangent(start: Point3D, end: Point3D, arc: (circle: Circle3D, from: Double, to: Double)?) throws -> Vector3D {
        guard let arc else { return try (end - start).normalized(tolerance: tolerance.distance) }
        let middle = try runMiddle(start: start, end: end, arc: arc)
        let radial = try (middle - arc.circle.center).normalized(tolerance: tolerance.distance)
        return try (arc.circle.normal.cross(radial) * (arc.to >= arc.from ? 1 : -1)).normalized(tolerance: tolerance.distance)
    }

    /// +1 when the wall rises from the cap along the edge, −1 when it falls, 0 when it runs along
    /// the cap: the side of the cap's
    /// plane the wall lies on beside the edge's middle — to the left of the edge as the wall's loop
    /// runs it (against the cap's run) about the wall's outward normal. A wall may cross the cap's
    /// plane elsewhere (a boss's wall running on down past a step).
    private func wallSide(_ wall: FaceID, edgeID: EdgeID, capTangent: Vector3D, middle: Point3D, cap: Vector3D,
                          model: BRepModel) throws -> Double {
        guard let face = model.faces[wall], let surface = model.geometry.surfaces[face.surfaceID] else {
            throw TopologyError.missingReference("Missing wall.")
        }
        let projected = try surface.parameterProjection(of: middle, tolerance: tolerance)
        let outward = try surface.normal(u: projected.u, v: projected.v, tolerance: tolerance) * (face.orientation == .forward ? 1 : -1)
        let into = outward.cross(capTangent * -1)
        let side = into.dot(cap)
        guard abs(side) > tolerance.angle * max(into.length, 1) else { return 0 }
        return side > 0 ? 1 : -1
    }

    private func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
        KernelError(phase: .evaluation, code: code, tolerance: tolerance, message: message)
    }
}
