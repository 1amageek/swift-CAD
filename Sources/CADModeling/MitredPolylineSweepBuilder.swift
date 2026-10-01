import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

/// A path-normal Sweep along a path of straight arms joined at mitred or round corners.
///
/// The section moves with the path's least-rotation frame: along an arm it slides, and at a
/// corner it turns by the least rotation taking the arm's direction to the next one's. Each arm
/// is the prism its section sweeps between the arm's two ends, each end the section pushed along
/// the arm onto the mitre plane through the corner (the plane whose normal is the sum of the two
/// directions), so neighbouring arms meet on that plane in the same curve. An open path is capped
/// by the section at its start and where the frame carries it at its end; a closed path closes on
/// itself when its frame comes back to where it started.
///
/// A round corner keeps the mitre on the inside of the turn and rounds the outside: the section is
/// split where it crosses the plane through the path holding the arm and the corner's axis (the
/// line through the corner across both arms), the outer pieces end on the plane across each arm
/// through the corner, and between those ends they turn about the axis by the corner's angle as
/// exact surfaces of revolution. A piece's end on the axis turns about nothing, so its face closes
/// at that point on the plane a line across the axis sweeps.
package struct MitredPolylineSweepBuilder {
    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// Whether a sweep takes this route: a path-normal sweep along straight spans with at least
    /// one corner between them.
    package static func applies(_ options: SweepOptions, pathSpans: [ExactBSplineCurveSpan], tolerance: ModelingTolerance) -> Bool {
        guard options.alignment == .normal, pathSpans.count >= 2,
              pathSpans.allSatisfy({ span in
                  let points = span.curve.controlPoints
                  guard let first = points.first, let last = points.last, (last - first).length > tolerance.distance else { return false }
                  let direction = (last - first) * (1 / (last - first).length)
                  return points.allSatisfy { let offset = $0 - first; return (offset - direction * offset.dot(direction)).length <= tolerance.distance }
              }) else { return false }
        return zip(pathSpans, pathSpans.dropFirst()).contains { before, after in
            let a = before.endPoint - before.startPoint, b = after.endPoint - after.startPoint
            return a.cross(b).length > sin(tolerance.angle) * a.length * b.length
        }
    }

    package struct Request {
        package let request: BRepSewingRequest
        package let armCount: Int
        package let includesCaps: Bool
        /// The section's spans per loop, after a round corner's splits.
        package let profileSpanCounts: [Int]
        /// The stable identities of round corners' faces, in corner, loop and span order.
        package let cornerFaceIDs: [String]
    }

    package func request(
        sectionLoops: [[ExactBSplineCurveSpan]],
        sectionIsClosed: Bool,
        profilePlane: SketchPlane,
        pathSpans: [ExactBSplineCurveSpan],
        pathIsClosed: Bool,
        options: SweepOptions,
        values: SweepOptionValues,
        featureID: FeatureID
    ) throws -> Request {
        try tolerance.validate()
        // FIXME(INCOMPLETE_IMPLEMENTATION): sweeps along a path with corners take no twist, end
        // scale or guides. Production path: MitredPolylineSweepBuilder for every path-normal
        // sweep along a path of straight arms. Complete only when a twist and scale run along the
        // arms and guides steer the section, verified by those sweeps' measured sections.
        guard values.twistAngle == 0, options.twistLaw == nil, values.endScale == 1 else {
            throw failure(.sweepRoundCornerUnavailable,
                "A sweep along a path with corners takes no twist or scale.", featureID)
        }
        guard options.resultKind == .sheet || sectionIsClosed else {
            throw failure(.invalidInput, "A solid sweep needs a closed section.", featureID)
        }
        guard values.distanceFraction == 1 else {
            throw failure(.invalidInput, "A sweep along a path with corners runs the whole path.", featureID)
        }
        let patches = ExactLinearSectionSweepFacePatchBuilder(tolerance: tolerance)
        let sectionPlane = try ExactSweepSectionPlane(profilePlane, tolerance: tolerance).plane
        for loop in sectionLoops {
            try patches.validateSectionContinuity(loop, isClosed: sectionIsClosed)
            try patches.validateProfileSpans(loop, on: sectionPlane)
        }
        // Arms: consecutive spans running the same way are one arm.
        var corners = [pathSpans[0].startPoint]
        var directions: [Vector3D] = []
        for span in pathSpans {
            let direction = try (span.endPoint - span.startPoint).normalized(tolerance: tolerance.distance)
            if let last = directions.last, last.cross(direction).length <= sin(tolerance.angle), last.dot(direction) > 0 {
                corners[corners.count - 1] = span.endPoint
            } else {
                directions.append(direction)
                corners.append(span.endPoint)
            }
        }
        let normal = try sectionPlane.normal.normalized(tolerance: tolerance.distance)
        if pathIsClosed {
            if directions.count > 1, let first = directions.first, let last = directions.last,
               last.cross(first).length <= sin(tolerance.angle), last.dot(first) > 0 {
                // The closing arm runs on into the first: one arm through the path's start.
                directions.removeFirst()
                corners = Array(corners[1..<(corners.count - 1)]) + [corners[1]]
            }
            // A closed path starts at the corner nearest the section, leaving along the arm that
            // runs most across the section's plane.
            let sectionPoints = sectionLoops.flatMap { $0.flatMap(\.curve.controlPoints) }
            let centroid = sectionPoints.reduce(Vector3D.zero) { $0 + ($1 - .origin) } * (1 / Double(max(sectionPoints.count, 1)))
            let ring = Array(corners.dropLast())
            guard let nearest = ring.indices.min(by: { (ring[$0] - .origin - centroid).length < (ring[$1] - .origin - centroid).length }) else {
                throw failure(.invalidInput, "A closed sweep path has no corners.", featureID)
            }
            var rotatedCorners = Array(ring[nearest...] + ring[..<nearest])
            var rotatedDirections = Array(directions[nearest...] + directions[..<nearest])
            if abs(normal.dot(rotatedDirections[rotatedDirections.count - 1])) > abs(normal.dot(rotatedDirections[0])) {
                rotatedCorners = [rotatedCorners[0]] + rotatedCorners.dropFirst().reversed()
                rotatedDirections = rotatedDirections.reversed().map { $0 * -1 }
            }
            corners = rotatedCorners + [rotatedCorners[0]]
            directions = rotatedDirections
        }
        let armCount = directions.count
        let advance = normal.dot(directions[0])
        guard abs(advance) > max(tolerance.relative, sin(tolerance.angle)) else {
            throw failure(.sweepProfilePlaneDegenerate, "The section's plane runs along the path.", featureID)
        }
        // The frame on each arm: the least rotations from the first arm's direction.
        var rotations = [Rotation.identity]
        for index in 1..<armCount {
            rotations.append(try Rotation(from: directions[index - 1], to: directions[index], tolerance: tolerance).composed(with: rotations[index - 1]))
        }
        if pathIsClosed {
            let closing = try Rotation(from: directions[armCount - 1], to: directions[0], tolerance: tolerance).composed(with: rotations[armCount - 1])
            guard closing.isIdentity(tolerance: tolerance) else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): a closed path whose frame comes back turned
                // (a non-planar loop) is refused. Production path: MitredPolylineSweepBuilder for
                // every closed path-normal sweep. Complete only when the turn is spread along the
                // arms as a twist, verified by a sweep around a non-planar closed polyline.
                throw failure(.sweepRoundCornerUnavailable,
                    "A closed sweep path brings its frame back turned; it must lie in a plane.", featureID)
            }
        }
        let origin = corners[0]
        // Round corners: corner `j` joins arm `j - 1` (the last arm for the closing corner) to arm
        // `j`; its inner side, carried back to the section's frame, splits the section.
        var roundCorners: [Int: RoundCorner] = [:]
        if options.cornerStyle == .round {
            for j in (pathIsClosed ? 0 : 1)..<armCount {
                let before = (j + armCount - 1) % armCount
                let (incoming, outgoing) = (directions[before], directions[j])
                let turn = incoming.cross(outgoing)
                let inner = try (outgoing - incoming * incoming.dot(outgoing)).normalized(tolerance: tolerance.distance)
                roundCorners[j] = RoundCorner(
                    before: before, point: corners[j],
                    axis: try turn.normalized(tolerance: tolerance.distance),
                    angle: atan2(turn.length, incoming.dot(outgoing)),
                    inner: rotations[before].transposed.applied(to: inner)
                )
            }
        }
        let loops = try splitSections(sectionLoops, origin: origin, across: roundCorners.values.map(\.inner))
        /// Whether a section span lies on the outer side of round corner `j`.
        func isOuter(_ span: ExactBSplineCurveSpan, corner j: Int) throws -> Bool {
            guard let corner = roundCorners[j] else { return false }
            let bounds = try patches.closedBounds(span.curve.domain)
            let middle = try Curve3D.bSpline(span.curve).point(at: 0.5 * (bounds.lower + bounds.upper), tolerance: tolerance)
            return (middle - origin).dot(corner.inner) < -tolerance.distance
        }
        /// Where a section point on arm `arm` meets its arm's start (`end` false) or end: the
        /// section's place at the path's ends, pushed along the arm onto the mitre plane, or for
        /// the outside of a round corner onto the plane across the arm through the corner.
        func place(_ point: Point3D, arm: Int, end: Bool, outer: Bool) throws -> Point3D {
            let offset = rotations[arm].applied(to: point - origin)
            let cornerIndex = end ? arm + 1 : arm
            let corner = corners[cornerIndex]
            if outer { return corner + (offset - directions[arm] * offset.dot(directions[arm])) }
            let neighbour: Vector3D?
            if end {
                neighbour = arm + 1 < armCount ? directions[arm + 1] : (pathIsClosed ? directions[0] : nil)
            } else {
                neighbour = arm > 0 ? directions[arm - 1] : (pathIsClosed ? directions[armCount - 1] : nil)
            }
            guard let neighbour else { return corner + offset }
            let mitre = directions[arm] + neighbour
            let along = directions[arm].dot(mitre)
            guard along > max(tolerance.relative, sin(tolerance.angle)) else {
                throw failure(.sweepRoundCornerUnavailable, "A sweep path turns back on itself at a corner.", featureID)
            }
            return corner + (offset - directions[arm] * (offset.dot(mitre) / along))
        }
        // Each arm's sides: per section span, the ruled surface between its two ends.
        var sides: [[BRepSewingFacePatch]] = loops.map { _ in [] }
        let windingSigns = try loops.map { loop in
            sectionIsClosed ? try patches.profileWindingSign(loop, normal: normal, featureID: featureID) : 1.0
        }
        let orientations: [Orientation] = windingSigns.map { sign in
            sectionIsClosed ? (sign * (advance > 0 ? 1 : -1) > 0 ? .forward : .reversed) : .forward
        }
        var startRows: [[BSplineCurve3D]] = loops.map { _ in [] }
        var endRows: [[BSplineCurve3D]] = loops.map { _ in [] }
        // Each arm's end rows, kept for the round corner after it.
        var armEndRows: [[[BSplineCurve3D]]] = []
        for arm in 0..<armCount {
            let endCorner = arm + 1 < armCount ? arm + 1 : (pathIsClosed ? 0 : -1)
            var armEnds: [[BSplineCurve3D]] = loops.map { _ in [] }
            for (loopIndex, loop) in loops.enumerated() {
                let orientation = orientations[loopIndex]
                for (spanIndex, span) in loop.enumerated() {
                    let outerAtStart = try isOuter(span, corner: arm)
                    let outerAtEnd = try isOuter(span, corner: endCorner)
                    let starts = try span.curve.controlPoints.map { try place($0, arm: arm, end: false, outer: outerAtStart) }
                    let ends = try span.curve.controlPoints.map { try place($0, arm: arm, end: true, outer: outerAtEnd) }
                    // The arm must run forward from its start to its end at every point.
                    for (start, end) in zip(starts, ends) where (end - start).dot(directions[arm]) <= tolerance.distance {
                        throw failure(.sweepRoundCornerUnavailable,
                            "The section is wider than an arm of the path allows at its mitres.", featureID)
                    }
                    let surface = BSplineSurface3D(
                        uDegree: span.curve.degree, vDegree: 1,
                        uKnots: span.curve.knots, vKnots: [0, 0, 1, 1],
                        controlPoints: [starts, ends], weights: [span.curve.weights, span.curve.weights]
                    )
                    try surface.validate(tolerance: tolerance)
                    sides[loopIndex].append(try patches.tensorSidePatch(
                        surface: surface, orientation: orientation,
                        stableID: loopIndex == 0
                            ? "sweep:side:path:\(arm):profile:\(spanIndex)"
                            : "sweep:side:path:\(arm):inner:\(loopIndex - 1):profile:\(spanIndex)"
                    ))
                    if arm == 0 { startRows[loopIndex].append(try surface.uIsoparametricCurve(atV: 0, tolerance: tolerance)) }
                    if arm == armCount - 1 { endRows[loopIndex].append(try surface.uIsoparametricCurve(atV: 1, tolerance: tolerance)) }
                    armEnds[loopIndex].append(try surface.uIsoparametricCurve(atV: 1, tolerance: tolerance))
                }
            }
            armEndRows.append(armEnds)
        }
        // Round corners' outer pieces turn about the corner's axis from one arm's end to the next
        // arm's start.
        var cornerFaceIDs: [String] = []
        for j in roundCorners.keys.sorted() {
            guard let corner = roundCorners[j] else { continue }
            for (loopIndex, loop) in loops.enumerated() {
                for (spanIndex, span) in loop.enumerated() where try isOuter(span, corner: j) {
                    let stableID = loopIndex == 0
                        ? "sweep:corner:\(j):profile:\(spanIndex)"
                        : "sweep:corner:\(j):inner:\(loopIndex - 1):profile:\(spanIndex)"
                    sides[loopIndex].append(try revolvedPatch(
                        armEndRows[corner.before][loopIndex][spanIndex], about: corner,
                        orientation: orientations[loopIndex], stableID: stableID, patches: patches
                    ))
                    cornerFaceIDs.append(stableID)
                }
            }
        }
        let includesCaps = options.resultKind == .solid && !pathIsClosed
        var caps: [BRepSewingFacePatch] = []
        if includesCaps {
            caps.append(try cap(startRows, normal: normal, outerWinding: windingSigns[0], advance: advance, atEnd: false, patches: patches))
            caps.append(try cap(endRows, normal: rotations[armCount - 1].applied(to: normal), outerWinding: windingSigns[0],
                                advance: advance, atEnd: true, patches: patches))
        }
        let request: BRepSewingRequest
        if options.resultKind == .solid {
            request = BRepSewingRequest(featureID: featureID, bodyKind: .solid,
                shells: [BRepSewingShell(stableID: "sweep:shell", patches: caps + sides.flatMap { $0 })])
        } else {
            request = BRepSewingRequest(featureID: featureID, bodyKind: .sheet, shells: sides.enumerated().map { index, patches in
                BRepSewingShell(stableID: index == 0 ? "sweep:shell" : "sweep:inner:\(index - 1):shell", patches: patches)
            })
        }
        return Request(request: request, armCount: armCount, includesCaps: includesCaps,
                       profileSpanCounts: loops.map(\.count), cornerFaceIDs: cornerFaceIDs)
    }

    /// `loops` with each span split where it crosses one of the planes through `origin` across
    /// `normals`, so every piece lies on one side of each.
    private func splitSections(
        _ loops: [[ExactBSplineCurveSpan]], origin: Point3D, across normals: [Vector3D]
    ) throws -> [[ExactBSplineCurveSpan]] {
        var planes: [Vector3D] = []
        for normal in normals where !planes.contains(where: { abs($0.dot(normal)) > 1 - 1e-12 }) {
            planes.append(normal)
        }
        guard !planes.isEmpty else { return loops }
        let eps = tolerance.distance * 1e-3
        return try loops.map { loop in
            try loop.flatMap { span -> [ExactBSplineCurveSpan] in
                let curve = Curve3D.bSpline(span.curve)
                let bounds = try ExactLinearSectionSweepFacePatchBuilder(tolerance: tolerance).closedBounds(span.curve.domain)
                var roots: [Double] = []
                for normal in planes {
                    func side(_ t: Double) throws -> Double { (try curve.point(at: t, tolerance: tolerance) - origin).dot(normal) }
                    let count = 128
                    let parameters = (0...count).map { bounds.lower + (bounds.upper - bounds.lower) * Double($0) / Double(count) }
                    let values = try parameters.map(side)
                    func sign(_ value: Double) -> Int { abs(value) <= eps ? 0 : (value > 0 ? 1 : -1) }
                    var previous: (parameter: Double, sign: Int)?
                    for (index, (t, value)) in zip(parameters, values).enumerated() where sign(value) != 0 {
                        defer { previous = (t, sign(value)) }
                        guard let last = previous, last.sign != sign(value) else { continue }
                        // A zero between them is the crossing; otherwise bisect for it.
                        if let zero = (0..<index).reversed().first(where: { parameters[$0] > last.parameter && sign(values[$0]) == 0 }) {
                            roots.append(parameters[zero])
                            continue
                        }
                        var (low, high) = (last.parameter, t)
                        for _ in 0..<80 {
                            let middle = 0.5 * (low + high)
                            if sign(try side(middle)) == last.sign { low = middle } else { high = middle }
                        }
                        roots.append(0.5 * (low + high))
                    }
                }
                let cuts = roots.filter { $0 - bounds.lower > tolerance.angle && bounds.upper - $0 > tolerance.angle }.sorted()
                guard !cuts.isEmpty else { return [span] }
                let breaks = [bounds.lower] + cuts + [bounds.upper]
                return try zip(breaks, breaks.dropFirst()).compactMap { lower, upper in
                    guard upper - lower > tolerance.angle else { return nil }
                    return try ExactBSplineCurveSpan(curve: span.curve.trimmed(from: lower, to: upper, tolerance: tolerance), tolerance: tolerance)
                }
            }
        }
    }

    /// The surface `row` sweeps turning about `corner`'s axis by its angle, rational quadratic in
    /// the turn (two pieces past a right angle), bounded by `row`, the turned row and the arcs its
    /// ends trace; an end on the axis traces none, so the face closes there.
    private func revolvedPatch(
        _ row: BSplineCurve3D, about corner: RoundCorner, orientation: Orientation, stableID: String,
        patches: ExactLinearSectionSweepFacePatchBuilder
    ) throws -> BRepSewingFacePatch {
        let pieces = corner.angle > 0.5 * Double.pi + tolerance.angle ? 2 : 1
        let step = corner.angle / Double(pieces)
        func turned(_ offset: Vector3D, by angle: Double) -> Vector3D {
            offset * cos(angle) + corner.axis.cross(offset) * sin(angle)
        }
        var rows: [[Point3D]] = []
        var weights: [[Double]] = []
        for piece in 0...pieces {
            let angle = step * Double(piece)
            rows.append(row.controlPoints.map { point in
                let center = corner.point + corner.axis * (point - corner.point).dot(corner.axis)
                return center + turned(point - center, by: angle)
            })
            weights.append(row.weights)
            guard piece < pieces else { break }
            rows.append(row.controlPoints.map { point in
                let center = corner.point + corner.axis * (point - corner.point).dot(corner.axis)
                let offset = point - center
                return center + (turned(offset, by: angle) + turned(offset, by: angle + step)) * (1 / (1 + cos(step)))
            })
            weights.append(row.weights.map { $0 * cos(0.5 * step) })
        }
        let vKnots = pieces == 1 ? [0.0, 0, 0, 1, 1, 1] : [0.0, 0, 0, 0.5, 0.5, 1, 1, 1]
        let surface = BSplineSurface3D(uDegree: row.degree, vDegree: 2, uKnots: row.knots, vKnots: vKnots,
                                       controlPoints: rows, weights: weights)
        try surface.validate(tolerance: tolerance)
        let u = try patches.closedBounds(surface.uDomain)
        let v = try patches.closedBounds(surface.vDomain)
        func onAxis(_ point: Point3D) -> Bool {
            let offset = point - corner.point
            return (offset - corner.axis * offset.dot(corner.axis)).length <= tolerance.distance
        }
        let rowCurve = Curve3D.bSpline(row)
        let startOnAxis = onAxis(try rowCurve.point(at: u.lower, tolerance: tolerance))
        let endOnAxis = onAxis(try rowCurve.point(at: u.upper, tolerance: tolerance))
        // The boundary: the row, the arc its end traces, the turned row back, and the arc its
        // start traces; an end on the axis traces none.
        var boundary: [(curve: BSplineCurve3D, reversed: Bool, pcurve: SurfaceParameterCurve, name: String)] = [
            (try surface.uIsoparametricCurve(atV: v.lower, tolerance: tolerance), false,
             .constantV(v: v.lower, uStart: u.lower, uEnd: u.upper), "bottom")]
        if !endOnAxis {
            boundary.append((try surface.vIsoparametricCurve(atU: u.upper, tolerance: tolerance), false,
                             .constantU(u: u.upper, vStart: v.lower, vEnd: v.upper), "end"))
        }
        boundary.append((try surface.uIsoparametricCurve(atV: v.upper, tolerance: tolerance), true,
                         .constantV(v: v.upper, uStart: u.upper, uEnd: u.lower), "top"))
        if !startOnAxis {
            boundary.append((try surface.vIsoparametricCurve(atU: u.lower, tolerance: tolerance), true,
                             .constantU(u: u.lower, vStart: v.upper, vEnd: v.lower), "start"))
        }
        guard startOnAxis || endOnAxis else {
            let edges = try boundary.map { try patches.exactEdge($0.curve, reversed: $0.reversed, surfaceParameterCurve: $0.pcurve,
                                                                 stableID: "\(stableID):\($0.name)") }
            let patch = BRepSewingFacePatch(stableID: stableID, surface: .bSpline(surface), orientation: orientation,
                loops: [BRepSewingLoop(stableID: "\(stableID):loop", role: .outer, edges: edges)])
            try patch.validate(tolerance: tolerance)
            return patch
        }
        // A piece reaching the axis turns into a face closing at it. The tensor surface has a pole
        // there, so the face takes the exact surface on which that point is regular: the plane a
        // line across the axis sweeps.
        let support = try apexSupport(row, corner: corner)
        let middle = try surface.differentialGeometry(u: 0.5 * (u.lower + u.upper), v: 0.5 * (v.lower + v.upper), tolerance: tolerance)
        let outward = middle.tangentU.cross(middle.tangentV) * (orientation == .forward ? 1 : -1)
        let projected = try support.parameterProjection(of: middle.position, tolerance: tolerance)
        let supportNormal = try support.normal(u: projected.u, v: projected.v, tolerance: tolerance)
        let pcurves = ExactFacePcurveBuilder()
        let edges = try boundary.map { side in
            let bounds = try patches.closedBounds(side.curve.domain)
            let pcurve = try pcurves.surfaceParameterCurve(
                for: .bSpline(side.curve),
                startParameter: side.reversed ? bounds.upper : bounds.lower,
                endParameter: side.reversed ? bounds.lower : bounds.upper,
                on: support, tolerance: tolerance
            )
            return try patches.exactEdge(side.curve, reversed: side.reversed, surfaceParameterCurve: pcurve,
                                         stableID: "\(stableID):\(side.name)")
        }
        let patch = BRepSewingFacePatch(stableID: stableID, surface: support,
            orientation: supportNormal.dot(outward) > 0 ? .forward : .reversed,
            loops: [BRepSewingLoop(stableID: "\(stableID):loop", role: .outer, edges: edges)])
        try patch.validate(tolerance: tolerance)
        return patch
    }

    /// The exact surface a section piece reaching `corner`'s axis sweeps when it turns about it.
    private func apexSupport(_ row: BSplineCurve3D, corner: RoundCorner) throws -> Surface3D {
        let bounds = try ExactLinearSectionSweepFacePatchBuilder(tolerance: tolerance).closedBounds(row.domain)
        let samples = try (0...8).map { try Curve3D.bSpline(row).point(at: bounds.lower + (bounds.upper - bounds.lower) * Double($0) / 8, tolerance: tolerance) }
        let first = samples[0], last = samples[8]
        let chord = last - first
        // A line across the axis sweeps the plane through the corner across the axis.
        if samples.allSatisfy({ ($0 - first).cross(chord).length <= tolerance.distance * chord.length }),
           abs(chord.dot(corner.axis)) <= tolerance.distance {
            return .plane(Plane3D(origin: first, normal: corner.axis))
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): a section piece reaching the corner's axis other than a
        // line across it (an arc of a circle making a sphere, a slanted line making a cone, a
        // spline) turns into a face whose exact surface shares no edge representation with the
        // arms' tensor faces, or whose tensor surface has a pole, so it is refused. Production
        // path: MitredPolylineSweepBuilder for Round corners. Complete only when such faces sew
        // with the arms, verified by Round sweeps of a circle, a diamond and an ellipse.
        throw KernelError(phase: .evaluation, code: .unsupportedCapability, tolerance: tolerance,
                          message: "A Round corner turns a section piece reaching its axis only as a line across it.")
    }

    private func cap(
        _ rows: [[BSplineCurve3D]], normal: Vector3D, outerWinding: Double, advance: Double, atEnd: Bool,
        patches: ExactLinearSectionSweepFacePatchBuilder
    ) throws -> BRepSewingFacePatch {
        let stableID = atEnd ? "sweep:cap:end" : "sweep:cap:start"
        let reversed = !atEnd
        let boundarySign = reversed ? -outerWinding : outerWinding
        let desiredSign = (atEnd ? 1.0 : -1.0) * (advance > 0 ? 1 : -1)
        guard let first = rows.first?.first else { throw FeatureEvaluationError.emptyResult("A mitred sweep's cap has no section span.") }
        let surface = Surface3D.plane(Plane3D(
            origin: try Curve3D.bSpline(first).point(at: patches.closedBounds(first.domain).lower, tolerance: tolerance),
            normal: normal * boundarySign
        ))
        let loops = try rows.enumerated().map { loopIndex, loop in
            let prefix = loopIndex == 0 ? stableID : "\(stableID):inner:\(loopIndex - 1)"
            let ordered = reversed ? Array(loop.indices.reversed()) : Array(loop.indices)
            return BRepSewingLoop(stableID: "\(prefix):loop", role: loopIndex == 0 ? .outer : .inner, edges: try ordered.map { index in
                try patches.exactEdge(loop[index], reversed: reversed,
                    surfaceParameterCurve: try patches.planarPcurve(loop[index], reversed: reversed, on: surface),
                    stableID: "\(prefix):edge:\(index)")
            })
        }
        let patch = BRepSewingFacePatch(stableID: stableID, surface: surface,
            orientation: boundarySign == desiredSign ? .forward : .reversed, loops: loops)
        try patch.validate(tolerance: tolerance)
        return patch
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ featureID: FeatureID) -> KernelError {
        KernelError(phase: .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
    }
}

/// A round corner: the arm before it, its point, the unit axis it turns about (across both arms),
/// the angle it turns by, and the unit inner direction across the arm before it carried back to
/// the section's frame.
private struct RoundCorner {
    let before: Int
    let point: Point3D
    let axis: Vector3D
    let angle: Double
    let inner: Vector3D
}

/// A rotation as a 3 × 3 matrix, composed from least rotations between unit directions.
private struct Rotation {
    let rows: [[Double]]

    static let identity = Rotation(rows: [[1, 0, 0], [0, 1, 0], [0, 0, 1]])

    init(rows: [[Double]]) {
        self.rows = rows
    }

    /// The least rotation taking unit `a` to unit `b`: `R v = (a·b) v + (a×b)×v + (a×b)((a×b)·v)/(1 + a·b)`.
    init(from a: Vector3D, to b: Vector3D, tolerance: ModelingTolerance) throws {
        let c = a.cross(b), d = a.dot(b)
        guard 1 + d > tolerance.relative else {
            throw KernelError(phase: .evaluation, code: .sweepRoundCornerUnavailable, tolerance: tolerance,
                message: "A sweep path turns back on itself at a corner.")
        }
        let k = 1 / (1 + d)
        let columns = [Vector3D.unitX, .unitY, .unitZ].map { v in v * d + c.cross(v) + c * (c.dot(v) * k) }
        rows = (0..<3).map { r in columns.map { [$0.x, $0.y, $0.z][r] } }
    }

    func applied(to v: Vector3D) -> Vector3D {
        Vector3D(
            x: rows[0][0] * v.x + rows[0][1] * v.y + rows[0][2] * v.z,
            y: rows[1][0] * v.x + rows[1][1] * v.y + rows[1][2] * v.z,
            z: rows[2][0] * v.x + rows[2][1] * v.y + rows[2][2] * v.z
        )
    }

    /// `self` after `other`.
    func composed(with other: Rotation) -> Rotation {
        Rotation(rows: (0..<3).map { r in (0..<3).map { c in (0..<3).reduce(0) { $0 + rows[r][$1] * other.rows[$1][c] } } })
    }

    var transposed: Rotation {
        Rotation(rows: (0..<3).map { r in (0..<3).map { c in rows[c][r] } })
    }

    func isIdentity(tolerance: ModelingTolerance) -> Bool {
        (0..<3).allSatisfy { r in (0..<3).allSatisfy { c in abs(rows[r][c] - (r == c ? 1 : 0)) <= max(tolerance.angle, 1e-12) } }
    }
}
